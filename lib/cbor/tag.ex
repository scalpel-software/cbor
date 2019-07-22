defmodule CBOR.Tag do
  @enforce_keys [:tag, :value]
  defstruct [:tag, :value]
end