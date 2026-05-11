defmodule CBOR.Utils do
  @moduledoc false
  def encode_head(mt, val, acc) when val < 24 do
    <<acc::binary, mt::size(3), val::size(5)>>
  end

  def encode_head(mt, val, acc) when val < 0x100 do
    <<acc::binary, mt::size(3), 24::size(5), val::size(8)>>
  end

  def encode_head(mt, val, acc) when val < 0x10000 do
    <<acc::binary, mt::size(3), 25::size(5), val::size(16)>>
  end

  def encode_head(mt, val, acc) when val < 0x100000000 do
    <<acc::binary, mt::size(3), 26::size(5), val::size(32)>>
  end

  def encode_head(mt, val, acc) when val < 0x10000000000000000 do
    <<acc::binary, mt::size(3), 27::size(5), val::size(64)>>
  end

  def encode_string(mt, s, acc) when byte_size(s) < 0x10000000000000000 do
    <<encode_head(mt, byte_size(s), acc)::binary, s::binary>>
  end

  def encode_string(_mt, s, acc) do
    <<acc::binary, 0x7F, s::binary, 0xFF>>
  end

  # Per RFC 8949 §4.1, preferred serialization picks the shortest IEEE 754
  # representation (binary16/32/64) that exactly preserves the value.
  # ±Infinity and NaN reach the wire through CBOR.Encoder for %CBOR.Tag{tag: :float, ...}
  # and never enter this function — only finite, non-NaN Floats arrive here.
  def encode_float(x, acc) when is_float(x) do
    cond do
      fits_in_half?(x) -> <<acc::binary, 0xF9, x::float-size(16)>>
      fits_in_single?(x) -> <<acc::binary, 0xFA, x::float-size(32)>>
      true -> <<acc::binary, 0xFB, x::float-size(64)>>
    end
  end

  # MatchError fires when the round-trip binary encodes to a half/single
  # +Inf/NaN bit pattern (e.g. `100_000.0` rounds to half-precision Inf):
  # the float-pattern LHS doesn't accept Inf/NaN bytes, so the match
  # fails. Narrow rescue keeps unrelated bugs visible.
  defp fits_in_half?(x) do
    <<roundtripped::float-size(16)>> = <<x::float-size(16)>>
    roundtripped === x
  rescue
    MatchError -> false
  end

  defp fits_in_single?(x) do
    <<roundtripped::float-size(32)>> = <<x::float-size(32)>>
    roundtripped === x
  rescue
    MatchError -> false
  end
end
