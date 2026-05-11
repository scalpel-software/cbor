defmodule CBOR.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Generators for "canonical" CBOR-encodable terms — values that survive
  # encode/decode bit-for-bit. Excludes shapes the encoder normalizes
  # (atoms → strings, tuples → lists, ranges → lists), which would need a
  # post-decode equivalence relation rather than `==`. NaN/±Inf go through
  # %CBOR.Tag{tag: :float, …} and are tested separately in unit tests.
  #
  # Depth is bounded explicitly rather than via StreamData.tree's
  # size-driven recursion. Without an explicit cap, the generator can
  # produce 5^k-sized trees (or worse) at large size values, making
  # individual iterations of round-trip blow the per-test timeout —
  # each level of map nesting recursively encodes its values to compute
  # sort keys and concat output.
  @max_term_depth 3
  @max_branch_fanout 5

  defp canonical_term, do: canonical_term(@max_term_depth)

  defp canonical_term(0), do: canonical_leaf()

  defp canonical_term(depth) do
    StreamData.frequency([
      {3, canonical_leaf()},
      {1, StreamData.list_of(canonical_term(depth - 1), max_length: @max_branch_fanout)},
      {1,
       StreamData.map_of(
         StreamData.string(:printable, max_length: 8),
         canonical_term(depth - 1),
         max_length: @max_branch_fanout
       )}
    ])
  end

  defp canonical_leaf do
    StreamData.one_of([
      StreamData.integer(),
      StreamData.string(:printable, max_length: 32),
      StreamData.binary(max_length: 32),
      StreamData.constant(nil),
      StreamData.boolean()
    ])
  end

  # Wider generator that includes shapes the encoder normalizes (atoms,
  # tuples) — used for the encoder no-raise property where we don't care
  # about structural equality after round-trip, only that encoding
  # doesn't crash. Map keys stay as strings to avoid collision-on-encode
  # (e.g. atom :foo and string "foo" both encode as text "foo", which
  # the encoder's dedup check would reject as a duplicate map key).
  defp encodable_term, do: encodable_term(@max_term_depth)

  defp encodable_term(0), do: encodable_leaf()

  defp encodable_term(depth) do
    StreamData.frequency([
      {3, encodable_leaf()},
      {1, StreamData.list_of(encodable_term(depth - 1), max_length: @max_branch_fanout)},
      {1,
       StreamData.map_of(
         StreamData.string(:printable, max_length: 8),
         encodable_term(depth - 1),
         max_length: @max_branch_fanout
       )}
    ])
  end

  defp encodable_leaf do
    StreamData.one_of([
      canonical_leaf(),
      StreamData.atom(:alphanumeric),
      finite_float()
    ])
  end

  # Generate any finite IEEE 754 float by random 64-bit pattern, filtering
  # out NaN and ±Inf (exponent = all 1s). Bypasses StreamData's
  # bounded-float generator, whose `power_of_two` walk doesn't shrink
  # enough at any practical bound to keep up with 50K iterations.
  defp finite_float do
    [length: 8]
    |> StreamData.binary()
    |> StreamData.filter(fn <<_sign::1, exp::11, _mant::52>> -> exp != 2047 end)
    |> StreamData.map(fn <<f::float-size(64)>> -> f end)
  end

  describe "round-trip" do
    property "encode then decode preserves canonical terms" do
      check all(term <- canonical_term(), max_runs: 5_000) do
        assert {:ok, decoded, ""} = CBOR.decode(CBOR.encode(term))
        assert decoded == term
      end
    end
  end

  # The public CBOR.decode/2 must classify every input as either a valid
  # decode or a typed error — never raise. Property covers both lenient
  # (default) and strict modes since strict mode adds throw-based paths
  # that should be caught at the public boundary.
  #
  # Binary length is bounded because random bytes can declare huge
  # array/map lengths (e.g. `<<0x9b 0xff×8>>`), causing the decoder to
  # loop for ~byte_size(rest) iterations before failing. Without a
  # bound, occasional pathological inputs blow the per-test timeout.
  # 256 bytes still covers every header form (uint8/16/32/64, all major
  # types, indefinite-length, tags) and runs in milliseconds.
  describe "no-raise" do
    property "decode/2 never raises on arbitrary binary (lenient)" do
      check all(bytes <- StreamData.binary(max_length: 256), max_runs: 50_000) do
        result = CBOR.decode(bytes)
        assert match?({:ok, _, _}, result) or match?({:error, _}, result)
      end
    end

    property "decode/2 never raises on arbitrary binary (strict)" do
      check all(bytes <- StreamData.binary(max_length: 256), max_runs: 50_000) do
        result = CBOR.decode(bytes, strict: true)
        assert match?({:ok, _, _}, result) or match?({:error, _}, result)
      end
    end

    property "decode/2 with EncodedCBOR registered never raises" do
      decoders = [CBOR.TagDecoders.EncodedCBOR]

      check all(bytes <- StreamData.binary(max_length: 256), max_runs: 50_000) do
        result = CBOR.decode(bytes, tag_decoders: decoders)
        assert match?({:ok, _, _}, result) or match?({:error, _}, result)
      end
    end
  end

  # If `CBOR.decode/1` accepts an arbitrary binary, encoding the result
  # and decoding again should produce the same term — i.e. decode lands
  # on a fixed point of `encode ∘ decode`. Catches encoder/decoder
  # asymmetry: any input the decoder accepts that the encoder can't
  # reproduce, or that re-decodes to a different value, is a real bug.
  # Runs against arbitrary bytes (not curated terms), so this property
  # is more demanding than the round-trip property above.
  describe "decoder stability" do
    property "decode result is a fixed point of encode ∘ decode" do
      check all(bytes <- StreamData.binary(max_length: 256), max_runs: 50_000) do
        case CBOR.decode(bytes) do
          {:ok, term, ""} ->
            assert {:ok, ^term, ""} = CBOR.decode(CBOR.encode(term))

          _ ->
            :ok
        end
      end
    end
  end

  # Encoder must produce a binary for any term covered by an
  # `CBOR.Encoder` protocol implementation. Documented raise classes:
  # ArgumentError (duplicate map keys after deterministic sort).
  # Anything else escaping is a bug. The generator uses string-only
  # map keys to steer clear of the documented dup-key path so any
  # ArgumentError that surfaces is genuinely surprising.
  describe "encoder" do
    property "encode/1 never raises on encodable terms" do
      check all(term <- encodable_term(), max_runs: 5_000) do
        _ = CBOR.encode(term)
      end
    end
  end

  # The encoder picks the shortest IEEE 754 form (binary16/32/64) that
  # exactly represents the value via a round-trip check. This property
  # fences that picker across the full IEEE 754 range. NaN/±Inf are
  # excluded by the generator (they encode via %CBOR.Tag{tag: :float, …}
  # and have their own unit-test coverage). Bit-pattern comparison
  # catches -0.0/0.0 sign preservation regressions: == treats them as
  # equal in Elixir, but they differ in encoded bytes.
  describe "float round-trip" do
    property "finite floats round-trip exactly through shortest-form encoding" do
      check all(f <- finite_float(), max_runs: 50_000) do
        {:ok, decoded, ""} = CBOR.decode(CBOR.encode(f))
        assert <<f::float-size(64)>> == <<decoded::float-size(64)>>
      end
    end
  end
end
