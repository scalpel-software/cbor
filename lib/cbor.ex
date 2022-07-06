defmodule CBOR do
  @moduledoc """
  The Concise Binary Object Representation (CBOR) is a data format
  whose design goals include the possibility of extremely small code
  size, fairly small message size, and extensibility without the need
  for version negotiation.  These design goals make it different from
  earlier binary serializations such as ASN.1 and MessagePack.

  The objectives of CBOR, roughly in decreasing order of importance are:

  1.  The representation must be able to unambiguously encode most
      common data formats used in Internet standards.

      *  It must represent a reasonable set of basic data types and
         structures using binary encoding.  "Reasonable" here is
         largely influenced by the capabilities of JSON, with the major
         addition of binary byte strings.  The structures supported are
         limited to arrays and trees; loops and lattice-style graphs
         are not supported.

       *  There is no requirement that all data formats be uniquely
          encoded; that is, it is acceptable that the number "7" might
          be encoded in multiple different ways.

  2.  The code for an encoder or decoder must be able to be compact in
      order to support systems with very limited memory, processor
      power, and instruction sets.

      *  An encoder and a decoder need to be implementable in a very
         small amount of code (for example, in class 1 constrained
         nodes as defined in [CNN-TERMS]).

      *  The format should use contemporary machine representations of
         data (for example, not requiring binary-to-decimal
         conversion).

  3.  Data must be able to be decoded without a schema description.

      *  Similar to JSON, encoded data should be self-describing so
          that a generic decoder can be written.

  4.  The serialization must be reasonably compact, but data
      compactness is secondary to code compactness for the encoder and
      decoder.

      *  "Reasonable" here is bounded by JSON as an upper bound in
         size, and by implementation complexity maintaining a lower
         bound.  Using either general compression schemes or extensive
         bit-fiddling violates the complexity goals.

  5.  The format must be applicable to both constrained nodes and high-
      volume applications.

      *  This means it must be reasonably frugal in CPU usage for both
         encoding and decoding.  This is relevant both for constrained
         nodes and for potential usage in applications with a very high
         volume of data.

  6.  The format must support all JSON data types for conversion to and
      from JSON.

      *  It must support a reasonable level of conversion as long as
         the data represented is within the capabilities of JSON.  It
         must be possible to define a unidirectional mapping towards
         JSON for all types of data.

  7.  The format must be extensible, and the extended data must be
      decodable by earlier decoders.

      *  The format is designed for decades of use.

      *  The format must support a form of extensibility that allows
         fallback so that a decoder that does not understand an
         extension can still decode the message.

      *  The format must be able to be extended in the future by later
         IETF standards.
  """

  @doc """
  Returns a binary encoding of the data in a format
  that can be interpreted by other CBOR libraries.

  ## Examples

      iex> CBOR.encode(["Hello", "World!"])
      <<130, 101, 72, 101, 108, 108, 111, 102, 87, 111, 114, 108, 100, 33>>

      iex> CBOR.encode([1, [2, 3]])
      <<130, 1, 130, 2, 3>>

      iex> CBOR.encode(%{"a" => 1, "b" => [2, 3]})
      <<162, 97, 97, 1, 97, 98, 130, 2, 3>>

  """
  @spec encode(any()) :: binary()
  def encode(value), do: CBOR.Encoder.encode_into(value, <<>>)

  @doc """
  Converts a CBOR encoded binary into native elixir data structures with a specified default
  decoder function. The function added should take a tag and a value, and the caller can
  specify how to decode the value associated to a tag input into the function.

  ## Examples

      iex(1)> bin_tuple = CBOR.encode(%CBOR.Tag{tag: 50, value: {1, 2, "tuple"}})
      <<216, 50, 131, 1, 2, 101, 116, 117, 112, 108, 101>>

      iex(2)> tuple_decoder = fn (tag, value) -> case tag, do: (50 -> List.to_tuple(value); _ -> CBOR.Decoder.default_decode_tag(tag, value)) end
      #Function<43.65746770/2 in :erl_eval.expr/5> # Note that non-matched tags are decoded using CBOR.Decoder.default_decode_tag/2

      iex> CBOR.decode(<<162, 97, 97, 1, 97, 98, 130, 2, 3>>)
      {:ok, %{"a" => 1, "b" => [2, 3]}, ""}

      iex(3)> CBOR.decode(bin_tuple, tuple_decoder)
      {:ok, {1, 2, "tuple"}, ""}

      iex(4)> bin_non_tuple = CBOR.encode(%CBOR.Tag{tag: 123, value: "Hello, World!"})
      <<216, 123, 109, 72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33>>

      iex(5)> CBOR.decode(bin_non_tuple, tuple_decoder)
      {:ok, %CBOR.Tag{tag: 123, value: "Hello, World!"}, ""}
  """
  @spec decode(binary()) :: {:ok, any(), binary()} | {:error, atom}
  def decode(binary) do
    try do
      perform_decoding(binary)
    rescue
      FunctionClauseError -> {:error, :cbor_function_clause_error}
    end
  end

  @doc """
  Converts a CBOR encoded binary into native elixir data structures

  """
  @spec decode(binary(), fun()) :: {:ok, any(), binary()} | {:error, atom}
  def decode(binary, default_decode) do
    try do
      perform_decoding(binary, default_decode)
    rescue
      FunctionClauseError -> {:error, :cbor_function_clause_error}
    end
  end

  defp perform_decoding(binary) when is_binary(binary) do
    case CBOR.Decoder.decode(binary) do
      {value, rest} -> {:ok, value, rest}
      _other -> {:error, :cbor_decoder_error}
    end
  end

  defp perform_decoding(_value), do: {:error, :cannot_decode_non_binary_values}

  defp perform_decoding(binary, default_decode) when is_binary(binary) do
    case CBOR.Decoder.decode(binary, default_decode) do
      {value, rest} -> {:ok, value, rest}
      _other -> {:error, :cbor_decoder_error}
    end
  end

  defp perform_decoding(_value, _function), do: {:error, :cannot_decode_non_binary_values}
end
