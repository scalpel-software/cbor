defmodule CBOR.Tag do
  @moduledoc """
  Wraps a value with a CBOR tag number, or marks one of the non-numeric
  tag-like shapes (`:bytes`, `:float`, `:simple`) the encoder/decoder
  treat specially.

  ## Examples

      # Raw byte string (CBOR major type 2):
      CBOR.encode(%CBOR.Tag{tag: :bytes, value: <<1, 2, 3>>})

      # IEEE 754 special floats — Elixir has no native representation:
      CBOR.encode(%CBOR.Tag{tag: :float, value: :inf})
      CBOR.encode(%CBOR.Tag{tag: :float, value: :"-inf"})
      CBOR.encode(%CBOR.Tag{tag: :float, value: :nan})

      # CBOR simple value:
      CBOR.encode(%CBOR.Tag{tag: :simple, value: 16})

      # Arbitrary CBOR tag number (RFC 8949 §3.4):
      CBOR.encode(%CBOR.Tag{tag: 1234, value: "payload"})

  The decoder produces this struct for CBOR values that don't have a
  built-in Elixir representation — unrecognized tags, simple values,
  ±infinity, and NaN.
  """
  @enforce_keys [:tag, :value]
  defstruct [:tag, :value]

  @typedoc "RFC 8949 §3.4 tag number — uint64 on the wire."
  @type tag_number :: non_neg_integer()

  @typedoc """
  Non-numeric tag-like markers the encoder/decoder treat specially:
  `:bytes` (CBOR major type 2), `:float` (NaN/±Inf), `:simple` (CBOR
  simple value).
  """
  @type tag_marker :: :bytes | :float | :simple

  @type t :: %__MODULE__{tag: tag_marker() | tag_number(), value: term()}
end
