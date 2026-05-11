defmodule CBOR.TagDecoders.EncodedCBORTest do
  use ExUnit.Case, async: true

  alias CBOR.TagDecoders.EncodedCBOR

  describe "registered as a tag_decoder" do
    # 0xd8 0x18 = tag 24; 0x44 = byte string of length 4; <<131, 1, 2, 3>> = [1, 2, 3]
    test "decodes tag 24 wrapping an encoded array" do
      encoded = <<0xD8, 0x18, 0x44, 131, 1, 2, 3>>

      assert CBOR.decode(encoded, tag_decoders: [EncodedCBOR]) ==
               {:ok, [1, 2, 3], ""}
    end

    # Inner: tag 24 wrapping <<1>> (integer 1 encoded as a single byte)
    # Outer: tag 24 wrapping the bytes of `inner`
    test "nested tag 24 unwraps fully because options (incl. tag_decoders) propagate" do
      inner = <<0xD8, 0x18, 0x41, 0x01>>
      outer = <<0xD8, 0x18, 0x44>> <> inner

      assert CBOR.decode(outer, tag_decoders: [EncodedCBOR]) == {:ok, 1, ""}
    end

    # Inner: 5-deep nested array = 6-deep root-to-leaf chain.
    # `ctx_to_opts` subtracts the outer call's `ctx.depth` from `max_depth`.
    # At the dispatch point, ctx.depth = 1 (the tag wrapper). The byte-string
    # wrapper is decoded in an inner `decode_value` call whose bumped ctx
    # doesn't propagate back, so it isn't subtracted — only the tag wrapper
    # counts. With max_depth: 4, inner gets 4 - 1 = 3 — too few for a 6-deep
    # chain, so the inner decode hits the limit. EncodedCBOR returns :error
    # and the wrapped form falls through.
    test "tag 24 inner decode inherits the outer max_depth budget" do
      inner_term = [[[[[1]]]]]
      inner_encoded = CBOR.encode(inner_term)
      outer_encoded = <<0xD8, 0x18, 0x40 + byte_size(inner_encoded)>> <> inner_encoded
      result = CBOR.decode(outer_encoded, tag_decoders: [EncodedCBOR], max_depth: 4)

      assert match?({:ok, %CBOR.Tag{tag: 24}, ""}, result)
    end

    test "tag 24 inner decode succeeds when the outer budget is sufficient" do
      inner_term = [[[1]]]
      inner_encoded = CBOR.encode(inner_term)
      outer_encoded = <<0xD8, 0x18, 0x40 + byte_size(inner_encoded)>> <> inner_encoded

      assert {:ok, decoded, ""} =
               CBOR.decode(outer_encoded, tag_decoders: [EncodedCBOR], max_depth: 6)

      assert decoded == inner_term
    end

    # Inner bytes 0x1c is reserved additional-info (28); header/1 has no clause.
    # 0xd8 0x18 = tag 24; 0x41 = byte string of length 1; 0x1c = malformed.
    test "tag 24 wrapping malformed bytes falls back to %CBOR.Tag" do
      encoded = <<0xD8, 0x18, 0x41, 0x1C>>

      expected = %CBOR.Tag{
        tag: 24,
        value: %CBOR.Tag{tag: :bytes, value: <<0x1C>>}
      }

      assert CBOR.decode(encoded, tag_decoders: [EncodedCBOR]) ==
               {:ok, expected, ""}
    end

    # 0xd8 0x18 = tag 24; 0x42 = byte string of length 2; 0x01 = integer 1; 0x02 = trailing
    test "tag 24 wrapping bytes with trailing garbage falls back to %CBOR.Tag" do
      encoded = <<0xD8, 0x18, 0x42, 0x01, 0x02>>

      expected = %CBOR.Tag{
        tag: 24,
        value: %CBOR.Tag{tag: :bytes, value: <<0x01, 0x02>>}
      }

      assert CBOR.decode(encoded, tag_decoders: [EncodedCBOR]) ==
               {:ok, expected, ""}
    end

    # 0xd8 0x18 = tag 24; 0x05 = integer 5 (not a byte string)
    test "tag 24 wrapping a non-byte-string content falls back to %CBOR.Tag" do
      encoded = <<0xD8, 0x18, 0x05>>

      assert CBOR.decode(encoded, tag_decoders: [EncodedCBOR]) ==
               {:ok, %CBOR.Tag{tag: 24, value: 5}, ""}
    end

    # 0xd8 0x18 = tag 24; 0x42 = byte string of length 2; 0x01 0x02 = trailing.
    # In lenient mode this falls back to %CBOR.Tag (see prior test). In
    # strict mode, the spec violation (RFC 8949 §3.4.5.1: tag 24 byte
    # string MUST contain exactly one well-formed CBOR data item) bubbles.
    test "strict + trailing bytes surfaces typed :tag_decoder_failed error" do
      encoded = <<0xD8, 0x18, 0x42, 0x01, 0x02>>

      assert CBOR.decode(encoded, strict: true, tag_decoders: [EncodedCBOR]) ==
               {:error, {:tag_decoder_failed, 24, :trailing_bytes_in_tag_24}}
    end

    # 0xd8 0x18 = tag 24; 0x41 = byte string of length 1; 0x1c = reserved AI 28.
    # Inner decode returns {:error, {:not_well_formed, :malformed_header}};
    # in strict mode EncodedCBOR passes that through.
    test "strict + malformed inner surfaces typed :tag_decoder_failed error" do
      encoded = <<0xD8, 0x18, 0x41, 0x1C>>

      assert CBOR.decode(encoded, strict: true, tag_decoders: [EncodedCBOR]) ==
               {:error, {:tag_decoder_failed, 24, {:not_well_formed, :malformed_header}}}
    end

    # Same as the lenient happy-path test, but with strict: true.
    test "strict + well-formed inner still succeeds (no regression)" do
      encoded = <<0xD8, 0x18, 0x44, 131, 1, 2, 3>>

      assert CBOR.decode(encoded, strict: true, tag_decoders: [EncodedCBOR]) ==
               {:ok, [1, 2, 3], ""}
    end

    test "without the decoder registered, tag 24 stays in its wrapped form" do
      encoded = <<0xD8, 0x18, 0x44, 131, 1, 2, 3>>

      expected = %CBOR.Tag{
        tag: 24,
        value: %CBOR.Tag{tag: :bytes, value: <<131, 1, 2, 3>>}
      }

      assert CBOR.decode(encoded) == {:ok, expected, ""}
    end
  end

  describe "tag_number/0" do
    test "returns 24" do
      assert EncodedCBOR.tag_number() == 24
    end
  end
end
