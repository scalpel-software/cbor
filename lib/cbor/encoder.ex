defprotocol CBOR.Encoder do
  @moduledoc """
  Protocol for serializing Elixir terms into CBOR.

  Implementations for built-in types (atoms, integers, floats, binaries,
  lists, maps, `Date`, `Time`, `DateTime`, `MapSet`, `URI`, `CBOR.Tag`,
  ...) ship with this library. Define your own `defimpl CBOR.Encoder, for: MyStruct`
  to teach `CBOR.encode/1` how to serialize custom types.
  """

  @doc """
  Append the CBOR encoding of `element` to `acc` and return the resulting
  binary.
  """
  @spec encode_into(t, binary) :: binary
  def encode_into(element, acc)
end

defimpl CBOR.Encoder, for: Atom do
  def encode_into(false, acc), do: <<acc::binary, 0xF4>>
  def encode_into(true, acc), do: <<acc::binary, 0xF5>>
  def encode_into(nil, acc), do: <<acc::binary, 0xF6>>
  def encode_into(:__undefined__, acc), do: <<acc::binary, 0xF7>>
  def encode_into(v, acc), do: CBOR.Utils.encode_string(3, Atom.to_string(v), acc)
end

defimpl CBOR.Encoder, for: BitString do
  def encode_into(s, acc), do: CBOR.Utils.encode_string(3, s, acc)
end

defimpl CBOR.Encoder, for: CBOR.Tag do
  def encode_into(%CBOR.Tag{tag: :bytes, value: s}, acc) do
    CBOR.Utils.encode_string(2, s, acc)
  end

  def encode_into(%CBOR.Tag{tag: :float, value: :inf}, acc) do
    <<acc::binary, 0xF9, 0x7C, 0>>
  end

  def encode_into(%CBOR.Tag{tag: :float, value: :"-inf"}, acc) do
    <<acc::binary, 0xF9, 0xFC, 0>>
  end

  def encode_into(%CBOR.Tag{tag: :float, value: :nan}, acc) do
    <<acc::binary, 0xF9, 0x7E, 0>>
  end

  # RFC 8949 §3.3: simple values 24..31 are reserved. The two-byte form
  # `<<0xF8, v>>` for `v < 32` is not well-formed (Appendix F subkind 2),
  # so the encoder refuses rather than emitting bytes that strict-mode
  # decode will reject as malformed.
  def encode_into(%CBOR.Tag{tag: :simple, value: val}, _acc) when val in 24..31 do
    raise ArgumentError,
          "CBOR simple values 24..31 are reserved (RFC 8949 §3.3) and cannot be encoded; got #{val}"
  end

  def encode_into(%CBOR.Tag{tag: :simple, value: val}, acc) when is_integer(val) and val >= 0 and val < 0x100 do
    CBOR.Utils.encode_head(7, val, acc)
  end

  # Out-of-range or non-integer simple values (RFC 8949 §3.3 caps simple
  # values at 0..255). Without this clause, the value falls through to the
  # generic `tag: tag, value: val` catch-all below and crashes inside
  # `encode_head/3` because `:simple` isn't a tag number.
  def encode_into(%CBOR.Tag{tag: :simple, value: val}, _acc) do
    raise ArgumentError,
          "CBOR simple values must be integers in 0..255 (RFC 8949 §3.3); got #{inspect(val)}"
  end

  # Tag 24 (Encoded CBOR data item, RFC 8949 §3.4.5.1): the wrapped content
  # MUST be a byte string. Two user-facing shapes are accepted, both producing
  # identical wire output:
  #   (1) %CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes, value: bin}} —
  #       user already encoded the inner CBOR data item.
  #   (2) %CBOR.Tag{tag: 24, value: <any Elixir term>} — auto-wrap: encode
  #       the term, then wrap those bytes in a CBOR byte string.
  def encode_into(%CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes} = bytes}, acc) do
    CBOR.Encoder.encode_into(bytes, CBOR.Utils.encode_head(6, 24, acc))
  end

  def encode_into(%CBOR.Tag{tag: 24, value: inner}, acc) do
    inner_bytes = CBOR.Encoder.encode_into(inner, <<>>)
    CBOR.Utils.encode_string(2, inner_bytes, CBOR.Utils.encode_head(6, 24, acc))
  end

  def encode_into(%CBOR.Tag{tag: tag, value: val}, acc) do
    CBOR.Encoder.encode_into(val, CBOR.Utils.encode_head(6, tag, acc))
  end
end

defimpl CBOR.Encoder, for: Date do
  def encode_into(date, acc) do
    CBOR.Encoder.encode_into(
      Date.to_iso8601(date),
      CBOR.Utils.encode_head(6, 1004, acc)
    )
  end
end

defimpl CBOR.Encoder, for: DateTime do
  def encode_into(datetime, acc) do
    CBOR.Encoder.encode_into(
      DateTime.to_iso8601(datetime),
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

defimpl CBOR.Encoder, for: Float do
  def encode_into(x, acc), do: CBOR.Utils.encode_float(x, acc)
end

defimpl CBOR.Encoder, for: Integer do
  def encode_into(i, acc) when i >= 0 and i < 0x10000000000000000 do
    CBOR.Utils.encode_head(0, i, acc)
  end

  def encode_into(i, acc) when i < 0 and i >= -0x10000000000000000 do
    CBOR.Utils.encode_head(1, -i - 1, acc)
  end

  def encode_into(i, acc) when i >= 0, do: encode_as_bignum(i, 2, acc)
  def encode_into(i, acc) when i < 0, do: encode_as_bignum(-i - 1, 3, acc)

  defp encode_as_bignum(i, tag, acc) do
    CBOR.Utils.encode_string(
      2,
      :binary.encode_unsigned(i),
      CBOR.Utils.encode_head(6, tag, acc)
    )
  end
end

defimpl CBOR.Encoder, for: List do
  def encode_into([], acc), do: <<acc::binary, 0x80>>

  def encode_into(list, acc) when length(list) < 0x10000000000000000 do
    Enum.reduce(list, CBOR.Utils.encode_head(4, length(list), acc), fn v, acc ->
      CBOR.Encoder.encode_into(v, acc)
    end)
  end

  def encode_into(list, acc) do
    Enum.reduce(list, <<acc::binary, 0x9F>>, fn v, acc ->
      CBOR.Encoder.encode_into(v, acc)
    end) <> <<0xFF>>
  end
end

defimpl CBOR.Encoder, for: Map do
  def encode_into(map, acc) when map_size(map) == 0, do: <<acc::binary, 0xA0>>

  # Per RFC 8949 §4.2.1 ("Core Deterministic Encoding"), map keys are sorted
  # by bytewise lexicographic order of their encoded forms — NOT the older
  # length-first ordering described in §4.2.3 (which CTAP2 and a few legacy
  # protocols use). Erlang term order over binaries happens to coincide with
  # bytewise lex (byte-by-byte, prefix-less), which is what `Enum.sort_by`
  # relies on. The encoder_test pins this with a cross-major-type case where
  # the two orderings disagree.
  #
  # We sort unconditionally — the wire is still valid CBOR for non-deterministic
  # consumers, and downstream protocols (COSE, etc.) that need deterministic
  # bytes get them by default.
  def encode_into(map, acc) when map_size(map) < 0x10000000000000000 do
    concat_pairs(encode_and_sort_pairs!(map), CBOR.Utils.encode_head(5, map_size(map), acc))
  end

  # Indefinite-length form (>= 2^64 entries) — unreachable on real Elixir
  # maps, but the same sort + dedup invariants apply if it ever fires.
  def encode_into(map, acc) do
    concat_pairs(encode_and_sort_pairs!(map), <<acc::binary, 0xBF>>) <> <<0xFF>>
  end

  defp encode_and_sort_pairs!(map) do
    map
    |> Enum.map(fn {k, v} ->
      {CBOR.Encoder.encode_into(k, <<>>), CBOR.Encoder.encode_into(v, <<>>), k}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> tap(&detect_duplicate_keys!/1)
  end

  defp concat_pairs(pairs, acc) do
    Enum.reduce(pairs, acc, fn {k, v, _orig}, a ->
      <<a::binary, k::binary, v::binary>>
    end)
  end

  # RFC 8949 §5.6 forbids duplicate keys; §4.2.1 (deterministic encoding)
  # restates this and §3.1 calls a map with duplicates "not well-formed."
  # Elixir maps already deduplicate by Elixir term equality, but the encoder
  # can still produce CBOR-level collisions because multiple distinct Elixir
  # terms map to the same encoded form: atoms encode as text strings (`:foo`
  # collides with `"foo"`), tuples and ranges encode as arrays (`{1,2}`
  # collides with `[1,2]`). Detect on encoded form after sort — adjacent
  # equal keys in a sorted list is a one-pass scan.
  defp detect_duplicate_keys!([{enc, _, k1}, {enc, _, k2} | _]) do
    raise ArgumentError,
          "duplicate CBOR map key: #{inspect(k1)} and #{inspect(k2)} encode to the same bytes (#{inspect(enc)}). " <>
            "RFC 8949 §5.6 requires map keys to be unique on the wire; atoms encode as text strings, tuples/ranges as arrays."
  end

  defp detect_duplicate_keys!([_ | rest]), do: detect_duplicate_keys!(rest)
  defp detect_duplicate_keys!([]), do: :ok
end

# MapSet round-trips via tag 258 (cbor-sets-spec) wrapping a CBOR array.
defimpl CBOR.Encoder, for: MapSet do
  def encode_into(map_set, acc) do
    map_set
    |> MapSet.to_list()
    |> CBOR.Encoder.encode_into(CBOR.Utils.encode_head(6, 258, acc))
  end
end

# We treat all NaiveDateTimes as UTC, if you need to include TimeZone
# information you should convert your data to a regular DateTime
defimpl CBOR.Encoder, for: NaiveDateTime do
  def encode_into(naive_datetime, acc) do
    CBOR.Encoder.encode_into(
      NaiveDateTime.to_iso8601(naive_datetime) <> "Z",
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

# CBOR has no range type, so a Range encodes as the array a List of the
# same elements would produce. The wire-equivalence test in
# `encoder_test.exs` pins this. Direct tail-recursion walks the range
# without materializing it as a list — measured ~2× faster than
# `Enum.to_list |> Enum.reduce` on a 1M-element range, with O(1) extra
# memory instead of O(n) cons cells. The Enumerable protocol's per-step
# overhead on Range is large enough that `Enum.reduce/3` directly on the
# range is *slower* than materializing first; only direct recursion wins.
defimpl CBOR.Encoder, for: Range do
  def encode_into(first..last//step = range, acc) do
    head_acc = CBOR.Utils.encode_head(4, Range.size(range), acc)
    walk(first, last, step, head_acc)
  end

  defp walk(first, last, step, acc) when step > 0 and first > last, do: acc
  defp walk(first, last, step, acc) when step < 0 and first < last, do: acc

  defp walk(first, last, step, acc) do
    walk(first + step, last, step, CBOR.Encoder.encode_into(first, acc))
  end
end

# CBOR has no IANA-registered tag for time-of-day. Tag 0 technically requires
# a full RFC 3339 date-time, so emitting it for a bare Time is out-of-spec —
# but it's what this library has always done, the decoder's fallback chain
# round-trips it back to Time, and switching to a plain text string would
# silently drop the type on read. Strict-mode decoders reject this, which is
# correct strict behavior.
defimpl CBOR.Encoder, for: Time do
  def encode_into(time, acc) do
    CBOR.Encoder.encode_into(
      Time.to_iso8601(time),
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

# We convert all Tuples to Lists since CBOR has no concept of Tuples,
# and they are basically the same thing anyway. This also fixes the problem
# of having to deal with keyword lists so we don't lose any information.
defimpl CBOR.Encoder, for: Tuple do
  def encode_into(tuple, acc) do
    tuple |> Tuple.to_list() |> CBOR.Encoder.encode_into(acc)
  end
end

defimpl CBOR.Encoder, for: URI do
  def encode_into(uri, acc) do
    CBOR.Encoder.encode_into(
      URI.to_string(uri),
      CBOR.Utils.encode_head(6, 32, acc)
    )
  end
end
