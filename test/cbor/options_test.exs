defmodule CBOR.OptionsTest do
  use ExUnit.Case, async: true

  defmodule UUIDDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 37

    @impl true
    def decode(%CBOR.Tag{tag: :bytes, value: bytes}) when byte_size(bytes) == 16 do
      {:ok, {:uuid, bytes}}
    end

    def decode(_), do: :error
  end

  defmodule BadBuiltinDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 0

    @impl true
    def decode(_value), do: :error
  end

  defmodule AnotherUUIDDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 37

    @impl true
    def decode(_), do: :error
  end

  defmodule WrapDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 42

    @impl true
    def decode(value), do: {:ok, {:wrapped, value}}
  end

  defmodule RaisingDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 99

    @impl true
    def decode(_), do: raise("boom")
  end

  defmodule ThrowingDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 98

    @impl true
    def decode(_), do: throw(:nope)
  end

  defmodule ImpersonatingDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 96

    @impl true
    # Throws a payload whose shape matches an internal control-flow throw —
    # `safely_call` must wrap it so it can't be mis-reported by the outer catch.
    def decode(_), do: throw({:cbor_max_depth_exceeded, 256})
  end

  defmodule BadReturnDecoder do
    @moduledoc false
    @behaviour CBOR.TagDecoder

    @impl true
    def tag_number, do: 97

    @impl true
    def decode(_), do: :totally_bogus
  end

  describe "tag_decoders option" do
    # 0xd8 0x25 = tag 37 (1-byte argument form); 0x50 = byte string of length 16
    test "custom decoder is dispatched for a non-built-in tag" do
      uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
      encoded = <<0xD8, 0x25, 0x50>> <> uuid

      assert CBOR.decode(encoded, tag_decoders: [UUIDDecoder]) ==
               {:ok, {:uuid, uuid}, ""}
    end

    # Tag 37 wrapping a 3-byte string (UUIDDecoder rejects: not 16 bytes)
    test "decoder returning :error falls back to %CBOR.Tag in lenient mode" do
      encoded = <<0xD8, 0x25, 0x43, 1, 2, 3>>

      expected = %CBOR.Tag{
        tag: 37,
        value: %CBOR.Tag{tag: :bytes, value: <<1, 2, 3>>}
      }

      assert CBOR.decode(encoded, tag_decoders: [UUIDDecoder]) == {:ok, expected, ""}
    end

    test "registering for a built-in tag raises ArgumentError" do
      assert_raise ArgumentError, ~r/built-in/, fn ->
        CBOR.decode(<<0x00>>, tag_decoders: [BadBuiltinDecoder])
      end
    end

    test "two decoders with the same tag raise ArgumentError" do
      assert_raise ArgumentError, ~r/conflict/, fn ->
        CBOR.decode(<<0x00>>, tag_decoders: [UUIDDecoder, AnotherUUIDDecoder])
      end
    end

    # Array of length 1 containing tag 37 + 16-byte UUID
    test "decoder is reachable from inside a nested array" do
      uuid = <<0::128>>
      encoded = <<0x81, 0xD8, 0x25, 0x50>> <> uuid

      assert CBOR.decode(encoded, tag_decoders: [UUIDDecoder]) ==
               {:ok, [{:uuid, uuid}], ""}
    end

    # Map with one UUID-tagged key/value and one tag-42-wrapped integer.
    # 0xa2 = map(2)
    # key1: 0xd8 0x25 0x50 + 16 bytes (tag 37 + bytes(16))
    # val1: integer 1
    # key2: text "n"
    # val2: 0xd8 0x2a 0x05 (tag 42 + integer 5)
    test "registry dispatches by tag — two distinct decoders both fire" do
      uuid = <<0::128>>
      encoded = <<0xA2, 0xD8, 0x25, 0x50>> <> uuid <> <<0x01, 0x61, ?n, 0xD8, 0x2A, 0x05>>

      assert CBOR.decode(encoded, tag_decoders: [UUIDDecoder, WrapDecoder]) ==
               {:ok, %{{:uuid, uuid} => 1, "n" => {:wrapped, 5}}, ""}
    end

    # 0xd8 0x2a = tag 42; 0x83 0x01 0x02 0x03 = array [1, 2, 3]
    test "decoder receives the recursively-decoded inner value, not raw bytes" do
      encoded = <<0xD8, 0x2A, 0x83, 0x01, 0x02, 0x03>>

      assert CBOR.decode(encoded, tag_decoders: [WrapDecoder]) ==
               {:ok, {:wrapped, [1, 2, 3]}, ""}
    end

    # Map with one entry: text "id" => tag 37 + 16-byte UUID
    test "decoder is reachable from inside a map value" do
      uuid = <<0::128>>
      encoded = <<0xA1, 0x62, ?i, ?d, 0xD8, 0x25, 0x50>> <> uuid

      assert CBOR.decode(encoded, tag_decoders: [UUIDDecoder]) ==
               {:ok, %{"id" => {:uuid, uuid}}, ""}
    end

    # 0xd8 0x63 = tag 99; 0x05 = integer 5
    test "decoder that raises is sandboxed and surfaces a typed error" do
      encoded = <<0xD8, 0x63, 0x05>>

      assert {:error, {:tag_decoder_raised, 99, {:raise, %RuntimeError{message: "boom"}}}} =
               CBOR.decode(encoded, tag_decoders: [RaisingDecoder])
    end

    # 0xd8 0x62 = tag 98; 0x05 = integer 5
    test "decoder that throws is sandboxed and surfaces a typed error" do
      encoded = <<0xD8, 0x62, 0x05>>

      assert CBOR.decode(encoded, tag_decoders: [ThrowingDecoder]) ==
               {:error, {:tag_decoder_raised, 98, {:throw, :nope}}}
    end

    # 0xd8 0x61 = tag 97; 0x05 = integer 5
    test "decoder that returns a non-conforming value surfaces a typed error" do
      encoded = <<0xD8, 0x61, 0x05>>

      assert CBOR.decode(encoded, tag_decoders: [BadReturnDecoder]) ==
               {:error, {:tag_decoder_raised, 97, {:bad_return, :totally_bogus}}}
    end

    # 0xd8 0x60 = tag 96; 0x05 = integer 5
    # ImpersonatingDecoder throws {:cbor_max_depth_exceeded, 256}. If the
    # outer catch matched on shape, this would be mis-reported as a
    # max-depth error. safely_call wraps it as :cbor_tag_decoder_raised so
    # the user's payload ends up nested inside {:throw, _}.
    test "user-decoder throw matching internal control-flow shape stays namespaced" do
      encoded = <<0xD8, 0x60, 0x05>>

      assert CBOR.decode(encoded, tag_decoders: [ImpersonatingDecoder]) ==
               {:error, {:tag_decoder_raised, 96, {:throw, {:cbor_max_depth_exceeded, 256}}}}
    end

    # 0x9f = begin indefinite array; 0xd8 0x2a = tag 42; 0x05 = int 5; 0xff = break
    test "decoder fires for a tagged value inside an indefinite-length array" do
      encoded = <<0x9F, 0xD8, 0x2A, 0x05, 0xFF>>

      assert CBOR.decode(encoded, tag_decoders: [WrapDecoder]) ==
               {:ok, [{:wrapped, 5}], ""}
    end
  end

  describe "decode_epoch_time option" do
    @epoch_int <<193, 26, 81, 75, 103, 176>>
    @epoch_float <<193, 251, 65, 212, 82, 217, 236, 32, 0, 0>>

    test "default (true) auto-decodes tag 1 + integer to DateTime" do
      assert CBOR.decode(@epoch_int) == {:ok, ~U[2013-03-21 20:04:00Z], ""}
    end

    test "false keeps tag 1 + integer as %CBOR.Tag" do
      assert CBOR.decode(@epoch_int, decode_epoch_time: false) ==
               {:ok, %CBOR.Tag{tag: 1, value: 1_363_896_240}, ""}
    end

    # 0xC1 = tag 1; 0xFB = float64; max double (~1.7976931348623157e308).
    # `trunc(value * 1_000_000)` overflows and would otherwise raise
    # ArithmeticError, which the public rescue does not catch.
    test "tag 1 with huge finite float falls back to %CBOR.Tag instead of crashing" do
      encoded = <<0xC1, 0xFB, 0x7F, 0xEF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

      assert {:ok, %CBOR.Tag{tag: 1, value: value}, ""} = CBOR.decode(encoded)
      assert is_float(value)
      assert value > 1.0e308
    end

    test "false keeps tag 1 + float as %CBOR.Tag" do
      assert CBOR.decode(@epoch_float, decode_epoch_time: false) ==
               {:ok, %CBOR.Tag{tag: 1, value: 1_363_896_240.5}, ""}
    end
  end

  describe "on_duplicate_key option" do
    # Map of two entries: "a" => 1, "a" => 2
    @duplicate_keys <<0xA2, 0x61, ?a, 0x01, 0x61, ?a, 0x02>>

    test "default :last_wins keeps the last value" do
      assert CBOR.decode(@duplicate_keys) == {:ok, %{"a" => 2}, ""}
    end

    test ":first_wins keeps the first value" do
      assert CBOR.decode(@duplicate_keys, on_duplicate_key: :first_wins) ==
               {:ok, %{"a" => 1}, ""}
    end

    test ":error returns an error tuple naming the duplicate key" do
      assert CBOR.decode(@duplicate_keys, on_duplicate_key: :error) ==
               {:error, {:duplicate_key, "a"}}
    end

    # Indefinite-length map: 0xbf ... 0xff
    # Two entries: "a" => 1, "a" => 2
    test ":error fires for duplicate keys inside an indefinite-length map" do
      encoded = <<0xBF, 0x61, ?a, 0x01, 0x61, ?a, 0x02, 0xFF>>

      assert CBOR.decode(encoded, on_duplicate_key: :error) ==
               {:error, {:duplicate_key, "a"}}
    end
  end

  describe "strict option" do
    test "rejects 0xf8 0x00 (reserved two-byte simple value form, RFC 8949 §3.3)" do
      assert CBOR.decode(<<0xF8, 0x00>>, strict: true) ==
               {:error, {:not_well_formed, :reserved_simple_value_form}}
    end

    test "rejects 0xf8 0x1f (last reserved two-byte simple value)" do
      assert CBOR.decode(<<0xF8, 0x1F>>, strict: true) ==
               {:error, {:not_well_formed, :reserved_simple_value_form}}
    end

    test "still accepts 0xf8 0x20 (simple value 32 — well-formed)" do
      assert CBOR.decode(<<0xF8, 0x20>>, strict: true) ==
               {:ok, %CBOR.Tag{tag: :simple, value: 32}, ""}
    end

    test "rejects indefinite-length on major type 0" do
      assert CBOR.decode(<<0x1F>>, strict: true) ==
               {:error, {:not_well_formed, :indefinite_length_not_allowed}}
    end

    test "rejects indefinite-length on major type 1" do
      assert CBOR.decode(<<0x3F>>, strict: true) ==
               {:error, {:not_well_formed, :indefinite_length_not_allowed}}
    end

    test "rejects indefinite-length on major type 6" do
      assert CBOR.decode(<<0xDF>>, strict: true) ==
               {:error, {:not_well_formed, :indefinite_length_not_allowed}}
    end

    test "rejects stray 0xff at top level" do
      assert CBOR.decode(<<0xFF>>, strict: true) ==
               {:error, {:not_well_formed, :stray_break_code}}
    end

    # 0x5F = begin indefinite byte string; 0x5F = nested indefinite (illegal
    # per RFC 8949 §3.2.3 / Appendix F subkind 5); 0xFF 0xFF = breaks.
    test "rejects nested indefinite-length byte string (chunk inside a chunk)" do
      assert CBOR.decode(<<0x5F, 0x5F, 0xFF, 0xFF>>, strict: true) ==
               {:error, {:not_well_formed, :nested_indefinite_string}}
    end

    # Without the throw, this previously raised an uncaught ArgumentError
    # from `<<value::binary-size(:indefinite), …>>` inside the parser.
    test "lenient mode also rejects nested indefinite-length byte string" do
      assert CBOR.decode(<<0x5F, 0x5F, 0xFF, 0xFF>>) ==
               {:error, {:not_well_formed, :nested_indefinite_string}}
    end

    # 0x7F = begin indefinite text string; 0x7F = nested indefinite (illegal).
    test "rejects nested indefinite-length text string" do
      assert CBOR.decode(<<0x7F, 0x7F, 0xFF, 0xFF>>) ==
               {:error, {:not_well_formed, :nested_indefinite_string}}
    end

    # 0xc2 = tag 2; 0x05 = integer 5
    test "rejects tag 2 with non-byte-string content (integer)" do
      assert CBOR.decode(<<0xC2, 0x05>>, strict: true) ==
               {:error, {:invalid_tag, 2, :non_byte_string_content}}
    end

    # 0xc2 = tag 2; 0x61 ?a = text string "a"
    test "rejects tag 2 with text-string content (no :bytes wrapper)" do
      assert CBOR.decode(<<0xC2, 0x61, ?a>>, strict: true) ==
               {:error, {:invalid_tag, 2, :non_byte_string_content}}
    end

    # 0xc3 = tag 3; 0x05 = integer 5
    test "tag 3 (negative bignum) with non-byte-string content rejects with tag 3" do
      assert CBOR.decode(<<0xC3, 0x05>>, strict: true) ==
               {:error, {:invalid_tag, 3, :non_byte_string_content}}
    end

    # 0xd8 0x20 = tag 32; 0x05 = integer 5
    test "rejects tag 32 with non-string content (integer)" do
      assert CBOR.decode(<<0xD8, 0x20, 0x05>>, strict: true) ==
               {:error, {:invalid_tag, 32, :not_uri_reference}}
    end

    # 0xd8 0x20 = tag 32; 0x76 = text-string-of-22; "http://www.example.com"
    test "tag 32 with a valid URI string still decodes" do
      encoded = <<0xD8, 0x20, 0x76, "http://www.example.com">>
      assert {:ok, %URI{}, ""} = CBOR.decode(encoded, strict: true)
    end

    # 0xf8 0x00 → wrapped simple value (round-trips via canonical single-byte form)
    test "lenient (default) accepts reserved simple values v < 20 as %CBOR.Tag" do
      assert {:ok, %CBOR.Tag{tag: :simple, value: 0}, ""} = CBOR.decode(<<0xF8, 0x00>>)
    end

    # Indefinite mt 0 — well-formedness violation in lenient mode
    test "reports malformed for disallowed indefinite" do
      assert {:error, {:not_well_formed, :malformed}} = CBOR.decode(<<0x1F>>)
    end

    # Stray 0xff at top level
    test "reports malformed for stray break" do
      assert {:error, {:not_well_formed, :malformed}} = CBOR.decode(<<0xFF>>)
    end

    # The two-byte form for v in 20..23 is malformed per §3.3, but the
    # canonical decoded value is unambiguous. Lenient normalizes so the
    # encode/decode round-trip is a fixed point.
    test "lenient normalizes 0xf8 + v in 20..23 to canonical false/true/nil/__undefined__" do
      assert {:ok, false, ""} = CBOR.decode(<<0xF8, 20>>)
      assert {:ok, true, ""} = CBOR.decode(<<0xF8, 21>>)
      assert {:ok, nil, ""} = CBOR.decode(<<0xF8, 22>>)
      assert {:ok, :__undefined__, ""} = CBOR.decode(<<0xF8, 23>>)
    end

    # No canonical single-byte form exists for these values, and the encoder
    # rejects %CBOR.Tag{tag: :simple, value: v in 24..31}. Wrapping would
    # produce a term the encoder can't serialize, so lenient also rejects.
    test "lenient rejects 0xf8 + v in 24..31 (truly unrepresentable)" do
      for v <- 24..31 do
        assert CBOR.decode(<<0xF8, v>>) ==
                 {:error, {:not_well_formed, :reserved_simple_value_form}}
      end
    end

    # Map with two "a" => N entries
    test "strict + on_duplicate_key: :error still fires :duplicate_key" do
      encoded = <<0xA2, 0x61, ?a, 0x01, 0x61, ?a, 0x02>>

      assert CBOR.decode(encoded, strict: true, on_duplicate_key: :error) ==
               {:error, {:duplicate_key, "a"}}
    end

    # Tag 37 wrapping a 3-byte string (UUIDDecoder rejects: not 16 bytes).
    # Strict mode shouldn't change the user-decoder fallback contract for
    # non-built-in tags.
    test "strict + custom decoder that returns :error still falls back to %CBOR.Tag" do
      encoded = <<0xD8, 0x25, 0x43, 1, 2, 3>>

      expected = %CBOR.Tag{
        tag: 37,
        value: %CBOR.Tag{tag: :bytes, value: <<1, 2, 3>>}
      }

      assert CBOR.decode(encoded, strict: true, tag_decoders: [UUIDDecoder]) ==
               {:ok, expected, ""}
    end

    # 0xd8 0x18 = tag 24; 0x41 = byte string of length 1; 0x1c = reserved AI 28.
    # Without EncodedCBOR registered, lenient mode wraps. Strict mode must
    # still validate the inner per RFC 8949 §3.4.5.1.
    test "tag 24 inner well-formedness fires under strict alone (no EncodedCBOR registered)" do
      encoded = <<0xD8, 0x18, 0x41, 0x1C>>

      assert CBOR.decode(encoded, strict: true) ==
               {:error, {:invalid_tag, 24, {:not_well_formed, :malformed_header}}}
    end

    # 0xd8 0x18 = tag 24; 0x42 = byte string of length 2; 0x01 0x02 = inner + trailing.
    test "tag 24 trailing bytes under strict alone surfaces :trailing_bytes_in_tag_24" do
      encoded = <<0xD8, 0x18, 0x42, 0x01, 0x02>>

      assert CBOR.decode(encoded, strict: true) ==
               {:error, {:invalid_tag, 24, :trailing_bytes_in_tag_24}}
    end

    # 0xd8 0x18 = tag 24; 0x05 = integer 5 (not a byte string).
    test "tag 24 with non-byte-string content under strict alone rejects" do
      encoded = <<0xD8, 0x18, 0x05>>

      assert CBOR.decode(encoded, strict: true) ==
               {:error, {:invalid_tag, 24, :non_byte_string_content}}
    end

    # Strict-only validation does not unwrap — the success-path shape is
    # the same as lenient-without-decoder. Caller opts into unwrapping
    # by registering EncodedCBOR.
    test "strict + tag 24 well-formed inner still wraps (no shape change without EncodedCBOR)" do
      encoded = <<0xD8, 0x18, 0x44, 131, 1, 2, 3>>

      expected = %CBOR.Tag{
        tag: 24,
        value: %CBOR.Tag{tag: :bytes, value: <<131, 1, 2, 3>>}
      }

      assert CBOR.decode(encoded, strict: true) == {:ok, expected, ""}
    end

    # Strict-only behavior; lenient must remain unchanged.
    test "lenient tag 24 with malformed inner still wraps (no validation)" do
      encoded = <<0xD8, 0x18, 0x41, 0x1C>>

      assert {:ok, %CBOR.Tag{tag: 24}, ""} = CBOR.decode(encoded)
    end

    # When the caller has registered EncodedCBOR, the decoder dispatch
    # route is the user-decoder path (apply_tag_decoder), so strict-mode
    # inner errors surface under :tag_decoder_failed — not the new
    # :invalid_tag namespace, which only fires when no decoder is registered.
    test "strict + EncodedCBOR registered keeps :tag_decoder_failed namespace" do
      encoded = <<0xD8, 0x18, 0x41, 0x1C>>

      assert CBOR.decode(encoded, strict: true, tag_decoders: [CBOR.TagDecoders.EncodedCBOR]) ==
               {:error, {:tag_decoder_failed, 24, {:not_well_formed, :malformed_header}}}
    end

    # A 5-deep inner term inside tag 24 + outer wrapper consumes the budget.
    # The inner validate receives `max_depth - ctx.depth` (1 already spent on
    # the tag wrapper), so `max_depth: 4` becomes `max_depth: 3` for the
    # inner decode — too few for the 5-deep chain, and the surfaced limit
    # reflects the inner budget, matching what `EncodedCBOR` propagates.
    test "tag 24 inner validation inherits the outer max_depth budget" do
      inner_term = [[[[[1]]]]]
      inner_encoded = CBOR.encode(inner_term)
      outer_encoded = <<0xD8, 0x18, 0x40 + byte_size(inner_encoded)>> <> inner_encoded

      assert CBOR.decode(outer_encoded, strict: true, max_depth: 4) ==
               {:error, {:invalid_tag, 24, {:max_depth_exceeded, 3}}}
    end

    # 0xd8 0x63 = tag 99; 0x05 = integer 5
    test "strict + raising custom decoder still surfaces :tag_decoder_raised" do
      encoded = <<0xD8, 0x63, 0x05>>

      assert {:error, {:tag_decoder_raised, 99, {:raise, %RuntimeError{message: "boom"}}}} =
               CBOR.decode(encoded, strict: true, tag_decoders: [RaisingDecoder])
    end
  end

  # Strict mode is documented as partial in CHANGELOG: certain RFC 8949
  # well-formedness rules are not yet enforced. These tests fence the
  # current boundary — if one flips from accept → reject (or shifts from
  # `:malformed_header` to a typed `:invalid_tag` reason), the gap was
  # closed.
  describe "strict option (documented partial-coverage gaps)" do
    # 0x18 0x05 is the 1-byte argument form for integer 5; preferred form
    # is 0x05. Strict mode does not enforce preferred-form integer heads.
    test "accepts non-preferred integer encoding (§4.2.1 violation)" do
      assert CBOR.decode(<<0x18, 0x05>>, strict: true) == {:ok, 5, ""}
    end

    # AI 28-30 is reserved per RFC 8949 §3. `header/1` has no clause →
    # FunctionClauseError → public rescue labels it `:malformed_header`.
    # No typed strict-mode reason for reserved AI values.
    test "reserved additional-info 28 surfaces as :malformed_header" do
      assert CBOR.decode(<<0x1C>>, strict: true) ==
               {:error, {:not_well_formed, :malformed_header}}
    end

    # binary64 NaN with non-zero mantissa payload (a signaling NaN).
    # RFC 8949 specifies canonical quiet NaN; strict does not reject others.
    test "accepts non-canonical NaN payload (§3.3 / §4.1 violation)" do
      encoded = <<0xFB, 0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01>>

      assert {:ok, %CBOR.Tag{tag: :float, value: :nan}, ""} =
               CBOR.decode(encoded, strict: true)
    end

    # 0xc2 = tag 2; 0x42 = bytes(2); <<0, 5>> = leading-zero bignum content.
    # §3.4.3 forbids leading zeros; strict does not enforce.
    test "accepts bignum with leading zero bytes (§3.4.3 violation)" do
      assert CBOR.decode(<<0xC2, 0x42, 0x00, 0x05>>, strict: true) == {:ok, 5, ""}
    end

    # 0xc2 = tag 2; 0x41 = bytes(1); <<5>>. §3.4.3 says SHOULD prefer the
    # integer form for values that fit; strict accepts the bignum form.
    test "accepts bignum that fits in uint64 (§3.4.3 SHOULD-prefer-integer)" do
      assert CBOR.decode(<<0xC2, 0x41, 0x05>>, strict: true) == {:ok, 5, ""}
    end

    # RFC 8949 §3.4.1 requires tag 0 to be a full date-time. The v1.x
    # compatibility chain decodes date-only strings as Date.
    test "tag 0 + date-only string decodes as Date via fallback chain" do
      encoded = <<0xC0, 0x6A, "2024-01-01">>
      assert CBOR.decode(encoded, strict: true) == {:ok, ~D[2024-01-01], ""}
    end

    # 0xc0 = tag 0; 0x05 = integer 5. `DateTime.from_iso8601(5)` raises
    # FunctionClauseError → public rescue labels it `:malformed_header`.
    # No typed `:invalid_tag` reason for tag 0 content validation.
    test "tag 0 + non-string content surfaces as :malformed_header" do
      assert CBOR.decode(<<0xC0, 0x05>>, strict: true) ==
               {:error, {:not_well_formed, :malformed_header}}
    end
  end

  describe "lenient tag 2/3 with non-byte-string content" do
    # Wire form is malformed per RFC 8949 §3.4.3 — bignum content must be
    # a byte string. v1.x silently coerced text-string bytes to a (negative)
    # bignum integer, a type-confusion path. v2 wraps in %CBOR.Tag{} so
    # callers can detect the wire-form error. Strict mode rejection is
    # tested in `describe "strict option"`.

    test "tag 2 + text string wraps in %CBOR.Tag (not coerced to bignum)" do
      assert CBOR.decode(<<0xC2, 0x68, "ABCDEFGH">>) ==
               {:ok, %CBOR.Tag{tag: 2, value: "ABCDEFGH"}, ""}
    end

    test "tag 3 + text string wraps in %CBOR.Tag (not coerced to negative bignum)" do
      assert CBOR.decode(<<0xC3, 0x68, "ABCDEFGH">>) ==
               {:ok, %CBOR.Tag{tag: 3, value: "ABCDEFGH"}, ""}
    end

    # Previously raised CaseClauseError → :not_well_formed; now wraps.
    test "tag 2 + integer wraps in %CBOR.Tag" do
      assert CBOR.decode(<<0xC2, 0x05>>) == {:ok, %CBOR.Tag{tag: 2, value: 5}, ""}
    end

    test "tag 3 + integer wraps in %CBOR.Tag" do
      assert CBOR.decode(<<0xC3, 0x05>>) == {:ok, %CBOR.Tag{tag: 3, value: 5}, ""}
    end

    test "tag 2 with valid byte-string content still decodes to bignum" do
      assert CBOR.decode(<<0xC2, 0x42, 0, 5>>) == {:ok, 5, ""}
    end

    test "tag 3 with valid byte-string content still decodes to negative bignum" do
      assert CBOR.decode(<<0xC3, 0x41, 0>>) == {:ok, -1, ""}
    end

    test "wrapped tag 2 round-trips through encode (fixed point)" do
      encoded = <<0xC2, 0x68, "ABCDEFGH">>
      {:ok, decoded, ""} = CBOR.decode(encoded)
      assert CBOR.encode(decoded) == encoded
    end
  end

  describe "option validation" do
    # Caller-bug invalid options used to surface as
    # `{:error, {:not_well_formed, :malformed_header}}` because the value
    # reached an inner clause that had no match (`put_with_policy/4` for
    # `:on_duplicate_key`) and the resulting FunctionClauseError was caught
    # by the public rescue. Now they raise ArgumentError up front with a
    # message that names the offending option and its expected shape.

    test "rejects unknown option key" do
      assert_raise ArgumentError, ~r/unknown CBOR\.decode option: :on_duplicate_keys/, fn ->
        CBOR.decode(<<0x05>>, on_duplicate_keys: :error)
      end
    end

    test "unknown-key error names the valid options" do
      assert_raise ArgumentError, ~r/Valid options:.*:on_duplicate_key/, fn ->
        CBOR.decode(<<0x05>>, mystery: :value)
      end
    end

    test "rejects invalid :on_duplicate_key value" do
      assert_raise ArgumentError, ~r/:on_duplicate_key.*one of.*:last_wins.*:first_wins.*:error/, fn ->
        CBOR.decode(<<0x05>>, on_duplicate_key: :bogus)
      end
    end

    test "rejects non-boolean :strict" do
      assert_raise ArgumentError, ~r/:strict.*must be a boolean/, fn ->
        CBOR.decode(<<0x05>>, strict: "yes")
      end
    end

    test "rejects non-boolean :decode_epoch_time" do
      assert_raise ArgumentError, ~r/:decode_epoch_time.*must be a boolean/, fn ->
        CBOR.decode(<<0x05>>, decode_epoch_time: 1)
      end
    end

    test "rejects non-integer :max_depth" do
      assert_raise ArgumentError, ~r/:max_depth.*positive integer/, fn ->
        CBOR.decode(<<0x05>>, max_depth: "deep")
      end
    end

    # max_depth: 0 would reject all input as exceeding depth — silly, and
    # the validator floors at 1 to keep the option's semantics meaningful.
    test "rejects :max_depth: 0 (boundary)" do
      assert_raise ArgumentError, ~r/:max_depth.*positive integer/, fn ->
        CBOR.decode(<<0x05>>, max_depth: 0)
      end
    end

    test "rejects negative :max_depth" do
      assert_raise ArgumentError, ~r/:max_depth.*positive integer/, fn ->
        CBOR.decode(<<0x05>>, max_depth: -1)
      end
    end

    test "accepts max_depth: 1 (boundary — single-item input)" do
      assert CBOR.decode(<<0x05>>, max_depth: 1) == {:ok, 5, ""}
    end

    test "rejects non-list :tag_decoders" do
      assert_raise ArgumentError, ~r/:tag_decoders.*list of CBOR\.TagDecoder modules/, fn ->
        CBOR.decode(<<0x05>>, tag_decoders: %{})
      end
    end

    test "rejects malformed entry (bare atom in opts list)" do
      assert_raise ArgumentError, ~r/keyword list.*got entry: :strict/, fn ->
        CBOR.decode(<<0x05>>, [:strict])
      end
    end

    test "rejects keyword entry with non-atom key" do
      assert_raise ArgumentError, ~r/keyword list.*got entry: \{"strict", true\}/, fn ->
        CBOR.decode(<<0x05>>, [{"strict", true}])
      end
    end

    # Empty input would otherwise FCE through `header/1` and surface as
    # :malformed_header — confirms validation gates early.
    test "validation runs before any decode work (smoke: bad option fires on empty input)" do
      assert_raise ArgumentError, ~r/:on_duplicate_key/, fn ->
        CBOR.decode(<<>>, on_duplicate_key: :bogus)
      end
    end
  end

  describe "max_depth option" do
    test "default rejects 257-deep nesting" do
      too_deep = Enum.reduce(1..256, 1, fn _, acc -> [acc] end)

      assert CBOR.decode(CBOR.encode(too_deep)) ==
               {:error, {:max_depth_exceeded, 256}}
    end

    # 255 nested arrays + 1 integer leaf = 256-deep root-to-leaf chain.
    test "default accepts 256-deep nesting" do
      ok_deep = Enum.reduce(1..255, 1, fn _, acc -> [acc] end)

      assert {:ok, decoded, ""} = CBOR.decode(CBOR.encode(ok_deep))
      assert decoded == ok_deep
    end

    test "custom small limit rejects shallower input" do
      assert CBOR.decode(CBOR.encode([[[1]]]), max_depth: 2) ==
               {:error, {:max_depth_exceeded, 2}}
    end

    test "custom large limit allows what default would reject" do
      deeper = Enum.reduce(1..299, 1, fn _, acc -> [acc] end)

      assert {:ok, decoded, ""} = CBOR.decode(CBOR.encode(deeper), max_depth: 500)
      assert decoded == deeper
    end

    # 5 nested maps + integer leaf = 6-deep chain. max_depth: 5 rejects it.
    test "limit applies to map nesting, not just arrays" do
      nested_map = Enum.reduce(1..5, 1, fn _, acc -> %{"k" => acc} end)

      assert CBOR.decode(CBOR.encode(nested_map), max_depth: 5) ==
               {:error, {:max_depth_exceeded, 5}}
    end

    # Three nested tag-8 wrappers around an integer 0. Tag 8 has no
    # built-in handler, so it preserves the wrapping shape. Chain:
    # tag → tag → tag → integer = 4 levels.
    test "limit applies to tag wrappers" do
      encoded = <<0xC8, 0xC8, 0xC8, 0x00>>

      assert CBOR.decode(encoded, max_depth: 3) ==
               {:error, {:max_depth_exceeded, 3}}
    end
  end
end
