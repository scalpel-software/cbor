defmodule CBOR.Utils do
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
    <<acc::binary, 0x7f, s::binary, 0xff>>
  end
end
