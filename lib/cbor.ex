defmodule CBOR do
  @moduledoc """
  Documentation for Cbor.
  """

  def encode(value), do: CBOR.Encoder.encode_into(value, <<>>)

  def decode(binary) do
    case CBOR.Decoder.decode(binary) do
      {value, ""} -> {:ok, value}
      _other -> {:error, :cbor_decoder_error}
    end
  end
end
