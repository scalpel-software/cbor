defmodule CBOR.EncoderTest do
  use ExUnit.Case, async: true

  defp reconstruct(value) do
    value |> CBOR.encode() |> CBOR.decode()
  end

  test "given the value of true" do
    assert reconstruct(true) == {:ok, true, ""}
  end

  test "given the value of false" do
    assert reconstruct(false) == {:ok, false, ""}
  end

  test "given the value of nil" do
    assert reconstruct(nil) == {:ok, nil, ""}
  end

  test "given the value of undefined" do
    assert reconstruct(:__undefined__) == {:ok, :__undefined__, ""}
  end

  test "given another atom (converts to string)" do
    assert reconstruct(:another_atom) == {:ok, "another_atom", ""}
  end

  test "given a large string" do
    assert reconstruct(String.duplicate("a", 20_000)) == {:ok, String.duplicate("a", 20_000), ""}
  end

  test "given an integer" do
    assert reconstruct(1) == {:ok, 1, ""}
  end

  test "given an bignum" do
    assert reconstruct(51_090_942_171_709_440_000) == {:ok, 51_090_942_171_709_440_000, ""}
  end

  test "given an negative bignum" do
    assert reconstruct(-51_090_942_171_709_440_000) == {:ok, -51_090_942_171_709_440_000, ""}
  end

  test "given a list with several items" do
    assert reconstruct([1, 2, 3, 4, 5, 6, 7, 8]) == {:ok, [1, 2, 3, 4, 5, 6, 7, 8], ""}
  end

  test "given an empty list" do
    assert reconstruct([]) == {:ok, [], ""}
  end

  test "given a complex nested list" do
    assert reconstruct([1, [2, 3], [4, 5]]) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "given a tuple, it converts it to a list" do
    assert reconstruct({}) == {:ok, [], ""}
  end

  test "given a tuple with several items" do
    assert reconstruct({1, 2, 3, 4, 5, 6, 7, 8}) == {:ok, [1, 2, 3, 4, 5, 6, 7, 8], ""}
  end

  test "given a complex nested tuple" do
    assert reconstruct({1, {2, 3}, {4, 5}}) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "given an empty  MapSet" do
    assert reconstruct(MapSet.new()) == {:ok, MapSet.new(), ""}
  end

  test "given a MapSet" do
    assert reconstruct(MapSet.new([1, 2, 3])) == {:ok, MapSet.new([1, 2, 3]), ""}
  end

  test "given a range" do
    assert reconstruct(1..10) == {:ok, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], ""}
  end

  test "an empty map" do
    assert reconstruct(%{}) == {:ok, %{}, ""}
  end

  test "a map with atom keys and values" do
    assert reconstruct(%{foo: :bar, baz: :quux}) == {:ok, %{"foo" => "bar", "baz" => "quux"}, ""}
  end

  test "complex maps" do
    assert reconstruct(%{"a" => 1, "b" => [2, 3]}) == {:ok, %{"a" => 1, "b" => [2, 3]}, ""}
  end

  test "tagged infinity" do
    assert reconstruct(%CBOR.Tag{tag: :float, value: :inf}) == {:ok, %CBOR.Tag{tag: :float, value: :inf}, ""}
  end

  test "tagged negative infinity" do
    assert reconstruct(%CBOR.Tag{tag: :float, value: :"-inf"}) == {:ok, %CBOR.Tag{tag: :float, value: :"-inf"}, ""}
  end

  test "tagged nan" do
    assert reconstruct(%CBOR.Tag{tag: :float, value: :nan}) == {:ok, %CBOR.Tag{tag: :float, value: :nan}, ""}
  end

  # %CBOR.Tag{tag: 24, value: [1, 2, 3]} should encode to:
  # 0xd8 0x18 = tag 24; 0x44 = byte string of length 4; <<131, 1, 2, 3>> = [1, 2, 3]
  test "tag 24 with an Elixir term auto-wraps the inner CBOR in a byte string" do
    assert CBOR.encode(%CBOR.Tag{tag: 24, value: [1, 2, 3]}) ==
             <<0xD8, 0x18, 0x44, 131, 1, 2, 3>>
  end

  test "tag 24 with a pre-wrapped %CBOR.Tag{tag: :bytes} produces the same wire output" do
    auto = CBOR.encode(%CBOR.Tag{tag: 24, value: [1, 2, 3]})

    pre_wrapped =
      CBOR.encode(%CBOR.Tag{
        tag: 24,
        value: %CBOR.Tag{tag: :bytes, value: <<131, 1, 2, 3>>}
      })

    assert auto == pre_wrapped
  end

  test "tag 24 round-trips through EncodedCBOR" do
    encoded = CBOR.encode(%CBOR.Tag{tag: 24, value: [1, 2, 3]})

    assert {:ok, [1, 2, 3], ""} =
             CBOR.decode(encoded, tag_decoders: [CBOR.TagDecoders.EncodedCBOR])
  end

  test "given a URI" do
    uri = URI.new!("http://www.example.com")

    assert reconstruct(uri) == {:ok, uri, ""}
  end

  test "given 0.0" do
    assert reconstruct(0.0) == {:ok, 0.0, ""}
  end

  test "given 0.1" do
    assert reconstruct(0.1) == {:ok, 0.1, ""}
  end

  test "given 1.0" do
    assert reconstruct(0.0) == {:ok, 0.0, ""}
  end

  test "given 1.1" do
    assert reconstruct(0.1) == {:ok, 0.1, ""}
  end

  test "more complex float" do
    assert reconstruct(123.1237987) == {:ok, 123.1237987, ""}
  end

  test "given a bignum" do
    assert reconstruct(2_432_902_008_176_640_000) == {:ok, 2_432_902_008_176_640_000, ""}
  end

  test "given a datetime" do
    assert reconstruct(~U[2013-03-21 20:04:00Z]) == {:ok, ~U[2013-03-21 20:04:00Z], ""}
  end

  test "given a naive datetime" do
    assert reconstruct(~N[2019-07-22 17:17:40.564490]) == {:ok, ~U[2019-07-22 17:17:40.564490Z], ""}
  end

  test "given a date" do
    assert reconstruct(~D[2000-01-01]) == {:ok, ~D[2000-01-01], ""}
  end

  test "given a time" do
    assert reconstruct(~T[23:00:07.001]) == {:ok, ~T[23:00:07.001], ""}
  end

  test "float shrinking: 0.0 encodes as binary16" do
    assert CBOR.encode(0.0) == <<0xF9, 0x00, 0x00>>
  end

  test "float shrinking: 1.0 encodes as binary16" do
    assert CBOR.encode(1.0) == <<0xF9, 0x3C, 0x00>>
  end

  test "float shrinking: 1.5 encodes as binary16" do
    assert CBOR.encode(1.5) == <<0xF9, 0x3E, 0x00>>
  end

  test "float shrinking: -4.0 encodes as binary16" do
    assert CBOR.encode(-4.0) == <<0xF9, 0xC4, 0x00>>
  end

  test "float shrinking: 65504.0 (max half-precision) encodes as binary16" do
    assert CBOR.encode(65_504.0) == <<0xF9, 0x7B, 0xFF>>
  end

  test "float shrinking: 100000.0 encodes as binary32 (out of half range)" do
    assert CBOR.encode(100_000.0) == <<0xFA, 0x47, 0xC3, 0x50, 0x00>>
  end

  test "float shrinking: 1.1 encodes as binary64 (no exact 32-bit rep)" do
    assert CBOR.encode(1.1) == <<0xFB, 0x3F, 0xF1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9A>>
  end

  test "float shrinking: smallest half subnormal encodes as binary16" do
    assert CBOR.encode(5.960464477539063e-8) == <<0xF9, 0x00, 0x01>>
  end

  test "float shrinking: 1.0e300 encodes as binary64 (out of single range)" do
    <<head, _::binary>> = CBOR.encode(1.0e300)
    assert head == 0xFB
  end

  test "negative zero round-trips with sign preserved" do
    encoded = CBOR.encode(-0.0)
    {:ok, decoded, ""} = CBOR.decode(encoded)
    assert <<1::1, _::63>> = <<decoded::float>>
  end

  # 0xd9 0x03 0xec = tag 1004; 0x6a = text-string-of-10
  test "Date encodes as tag 1004 + ISO 8601 full-date string (RFC 8943)" do
    assert CBOR.encode(~D[2000-01-01]) ==
             <<0xD9, 0x03, 0xEC, 0x6A, "2000-01-01">>
  end

  # 0xd9 0x01 0x02 = tag 258; 0x80 = empty array
  test "empty MapSet encodes as tag 258 + empty array (cbor-sets-spec)" do
    assert CBOR.encode(MapSet.new()) == <<0xD9, 0x01, 0x02, 0x80>>
  end

  # Tag 258 head (order of inner array is impl-defined; verify by round-trip)
  test "MapSet encodes with the tag 258 prefix and round-trips" do
    encoded = CBOR.encode(MapSet.new([1, 2, 3]))
    assert <<0xD9, 0x01, 0x02, _::binary>> = encoded
    assert CBOR.decode(encoded) == {:ok, MapSet.new([1, 2, 3]), ""}
  end

  # Insertion order puts "b" first, but encoded order must put "a" first.
  test "map keys are sorted by bytewise lex of encoded keys (RFC 8949 §4.2.1)" do
    expected = <<
      # map of 2
      0xA2,
      # key "a" => value 2
      0x61,
      ?a,
      0x02,
      # key "b" => value 1
      0x61,
      ?b,
      0x01
    >>

    assert CBOR.encode(%{"b" => 1, "a" => 2}) == expected
  end

  # Keys (encoded form) and values:
  #   10        (0x0a)            => 1
  #   100       (0x18 0x64)       => 2
  #   -1        (0x20)            => 3
  #   "z"       (0x61 0x7a)       => 4
  #   "aa"      (0x62 0x61 0x61)  => 5
  #   [100]     (0x81 0x18 0x64)  => 6
  #   [-1]      (0x81 0x20)       => 7
  #   false     (0xf4)            => 8
  test "deterministic key ordering matches RFC 8949 §4.2.1 mixed-type example" do
    m = %{
      10 => 1,
      100 => 2,
      -1 => 3,
      "z" => 4,
      "aa" => 5,
      [100] => 6,
      [-1] => 7,
      false => 8
    }

    expected = <<
      # map of 8
      0xA8,
      # 10 => 1
      0x0A,
      0x01,
      # 100 => 2
      0x18,
      0x64,
      0x02,
      # -1 => 3
      0x20,
      0x03,
      # "z" => 4
      0x61,
      0x7A,
      0x04,
      # "aa" => 5
      0x62,
      0x61,
      0x61,
      0x05,
      # [100] => 6
      0x81,
      0x18,
      0x64,
      0x06,
      # [-1] => 7
      0x81,
      0x20,
      0x07,
      # false => 8
      0xF4,
      0x08
    >>

    assert CBOR.encode(m) == expected
  end

  # 100 encodes to 2 bytes (<<0x18, 0x64>>); "" encodes to 1 byte (<<0x60>>).
  # The two RFC 8949 orderings disagree on this pair:
  #   Core (§4.2.1 — what we use): 100 sorts first because 0x18 < 0x60.
  #   Length-First (§4.2.3 — CTAP2): "" sorts first because length 1 < 2.
  # Most key pairs accidentally agree because CBOR's length-prefix byte
  # encodes length in its low bits, but cross-major-type pairs at the
  # short-encoding boundary expose the difference.
  # 0xa2 = map(2); 100 => 1: 0x18 0x64 0x01; "" => 2: 0x60 0x02
  test "map keys sort by RFC 8949 §4.2.1 Core (bytewise lex), not §4.2.3 Length-First" do
    encoded = CBOR.encode(%{100 => 1, "" => 2})
    assert encoded == <<0xA2, 0x18, 0x64, 0x01, 0x60, 0x02>>
  end

  # `:foo` and `"foo"` are distinct Elixir terms but both encode as the CBOR
  # text string "foo" — emitting both would violate RFC 8949 §5.6.
  test "duplicate encoded map keys raise (atom vs same-named string)" do
    assert_raise ArgumentError, ~r/duplicate CBOR map key/, fn ->
      CBOR.encode(%{:foo => 1, "foo" => 2})
    end
  end

  # Tuples encode as arrays, so `{1, 2}` and `[1, 2]` collide on the wire.
  test "duplicate encoded map keys raise (tuple vs list of same elements)" do
    assert_raise ArgumentError, ~r/duplicate CBOR map key/, fn ->
      CBOR.encode(%{{1, 2} => :a, [1, 2] => :b})
    end
  end

  test "encoding %CBOR.Tag{tag: :simple, value: v} for v in 24..31 raises (RFC 8949 §3.3 reserved)" do
    for v <- 24..31 do
      assert_raise ArgumentError, ~r/reserved/, fn ->
        CBOR.encode(%CBOR.Tag{tag: :simple, value: v})
      end
    end
  end

  # Smallest legal two-byte simple value.
  test "%CBOR.Tag{tag: :simple, value: 32} (boundary) encodes and round-trips" do
    assert CBOR.encode(%CBOR.Tag{tag: :simple, value: 32}) == <<0xF8, 0x20>>

    assert CBOR.decode(<<0xF8, 0x20>>) ==
             {:ok, %CBOR.Tag{tag: :simple, value: 32}, ""}
  end

  # RFC 8949 §3.3 caps simple values at 0..255 (1-byte argument form).
  # Without an explicit clause, this fell through to the generic tag
  # catch-all and crashed inside `encode_head/3` because `:simple` isn't
  # a tag number. Now raises ArgumentError with a clear message.
  test "encoding %CBOR.Tag{tag: :simple, value: v} for v >= 256 raises (out of range)" do
    assert_raise ArgumentError, ~r/integers in 0\.\.255/, fn ->
      CBOR.encode(%CBOR.Tag{tag: :simple, value: 256})
    end
  end

  test "encoding %CBOR.Tag{tag: :simple, value: v} for v < 0 raises" do
    assert_raise ArgumentError, ~r/integers in 0\.\.255/, fn ->
      CBOR.encode(%CBOR.Tag{tag: :simple, value: -1})
    end
  end

  test "encoding %CBOR.Tag{tag: :simple, value: v} for non-integer v raises" do
    assert_raise ArgumentError, ~r/integers in 0\.\.255/, fn ->
      CBOR.encode(%CBOR.Tag{tag: :simple, value: :nope})
    end
  end

  # CBOR has no range type, so a Range encodes as the same array a List
  # of the same elements would produce. This pins wire equivalence
  # regardless of how the Range impl is implemented internally
  # (materialize-then-list vs direct iteration).
  test "Range encoding produces identical wire bytes to encoding the equivalent List" do
    for range <- [0..0, 1..10, -5..5, 1..1000, 0..255//1] do
      assert CBOR.encode(range) == CBOR.encode(Enum.to_list(range)),
             "Range #{inspect(range)} did not match List encoding"
    end
  end

  # Outer map with one key whose value is an inner map. Both should sort.
  test "nested maps are also sorted" do
    m = %{"outer" => %{"b" => 1, "a" => 2}}
    encoded = CBOR.encode(m)

    expected_inner = <<0xA2, 0x61, ?a, 0x02, 0x61, ?b, 0x01>>

    expected = <<
      0xA1,
      0x65,
      "outer"::binary,
      expected_inner::binary
    >>

    assert encoded == expected
  end
end
