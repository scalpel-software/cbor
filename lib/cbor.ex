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

  ## Raises

  - `Protocol.UndefinedError` if no `CBOR.Encoder` implementation exists
    for the term's type (typically a custom struct). Add
    `defimpl CBOR.Encoder, for: MyStruct` to teach the encoder.
  - `ArgumentError` for wire-malformedness defenses:
    - Map with two keys that encode to identical bytes (RFC 8949 §5.6).
      `:foo`/`"foo"`, `{1,2}`/`[1,2]`, etc. encode identically and are
      rejected after the deterministic key sort. The error message
      names both colliding Elixir keys so the input bug can be fixed
      at the call site.
    - `%CBOR.Tag{tag: :simple, value: v}` with `v` in `24..31` —
      reserved per RFC 8949 §3.3 (Appendix F subkind 2).

  """
  @spec encode(any()) :: binary()
  def encode(value), do: CBOR.Encoder.encode_into(value, <<>>)

  @doc """
  Converts a CBOR encoded binary into native elixir data structures

  ## Examples

      iex> CBOR.decode(<<130, 101, 72, 101, 108, 108, 111, 102, 87, 111, 114, 108, 100, 33>>)
      {:ok, ["Hello", "World!"], ""}

      iex> CBOR.decode(<<130, 1, 130, 2, 3>>)
      {:ok, [1, [2, 3]], ""}

      iex> CBOR.decode(<<162, 97, 97, 1, 97, 98, 130, 2, 3>>)
      {:ok, %{"a" => 1, "b" => [2, 3]}, ""}

  Malformed input returns a typed error per `t:decode_error/0`:

      iex> CBOR.decode(<<>>)
      {:error, {:not_well_formed, :malformed_header}}

  """
  @typedoc """
  Reasons emitted with `{:not_well_formed, _}`. RFC 8949 App. F well-formedness
  violations and the three BEAM-class catch-alls (`:malformed_header`,
  `:truncated`, `:malformed`) the public rescue translates from internal
  parser exceptions.
  """
  @type not_well_formed_reason ::
          :malformed_header
          | :truncated
          | :malformed
          | :indefinite_length_not_allowed
          | :stray_break_code
          | :nested_indefinite_string
          | :reserved_simple_value_form

  @typedoc """
  Reasons emitted with `{:invalid_tag, tag, _}` for built-in tag content
  validation failures. The `{:not_well_formed, _}` variant nests the
  inner reason for tag 24 strict-mode validation, where the outer tag's
  spec violation is "byte string did not contain well-formed CBOR".
  """
  @type invalid_tag_reason ::
          :non_byte_string_content
          | :not_uri_reference
          | :trailing_bytes_in_tag_24
          | {:not_well_formed, not_well_formed_reason()}

  @typedoc """
  Shape of the third element in `{:tag_decoder_raised, tag, _}`. A user
  `CBOR.TagDecoder` that raises, throws, exits, or returns a non-conforming
  value is wrapped in one of these four forms.
  """
  @type tag_decoder_raised_reason ::
          {:raise, Exception.t()}
          | {:throw, term()}
          | {:exit, term()}
          | {:bad_return, term()}

  @typedoc """
  Error reasons returned by `decode/1` and `decode/2`.
  """
  @type decode_error ::
          :cannot_decode_non_binary_values
          | {:duplicate_key, term()}
          | {:not_well_formed, not_well_formed_reason()}
          | {:invalid_tag, non_neg_integer(), invalid_tag_reason()}
          | {:tag_decoder_raised, non_neg_integer(), tag_decoder_raised_reason()}
          | {:tag_decoder_failed, non_neg_integer(), term()}
          | {:max_depth_exceeded, non_neg_integer()}

  @spec decode(binary()) :: {:ok, term(), binary()} | {:error, decode_error()}
  @spec decode(binary(), keyword()) :: {:ok, term(), binary()} | {:error, decode_error()}
  def decode(binary, opts \\ []) do
    perform_decoding(binary, opts)
  rescue
    # `header/1` had no clause that matched — empty input, or reserved
    # additional-info values 28-30.
    FunctionClauseError -> {:error, {:not_well_formed, :malformed_header}}
    # `<<value::binary-size(len), …>> = rest` failed: the declared length
    # overran the available bytes.
    MatchError -> {:error, {:not_well_formed, :truncated}}
    # Catch-all for shapes the parser doesn't accept (lenient indefinite
    # on mt 0/1/6/7, stray break code, lenient tag 2 with non-byte content).
    CaseClauseError -> {:error, {:not_well_formed, :malformed}}
  end

  defp perform_decoding(binary, opts) when is_binary(binary) do
    {value, rest} = CBOR.Decoder.decode(binary, opts)
    {:ok, value, rest}
  catch
    {:cbor_duplicate_key, key} -> {:error, {:duplicate_key, key}}
    {:cbor_not_well_formed, reason} -> {:error, {:not_well_formed, reason}}
    {:cbor_invalid_tag, tag, reason} -> {:error, {:invalid_tag, tag, reason}}
    {:cbor_tag_decoder_raised, tag, reason} -> {:error, {:tag_decoder_raised, tag, reason}}
    {:cbor_tag_decoder_failed, tag, reason} -> {:error, {:tag_decoder_failed, tag, reason}}
    {:cbor_max_depth_exceeded, max} -> {:error, {:max_depth_exceeded, max}}
  end

  defp perform_decoding(_value, _opts), do: {:error, :cannot_decode_non_binary_values}

  @doc """
  Renders a `decode_error()` term as a human-readable message suitable for
  logging, error reporting, or surfacing to operators.

  ## Examples

      iex> CBOR.format_error({:not_well_formed, :truncated})
      "CBOR input ended mid-data-item (truncated)"

      iex> CBOR.format_error({:max_depth_exceeded, 256})
      "CBOR nesting exceeded the configured :max_depth of 256"

      iex> CBOR.format_error({:invalid_tag, 2, :non_byte_string_content})
      "CBOR tag 2 content was not a byte string (RFC 8949 §3.4.3)"

  """
  @spec format_error(decode_error()) :: String.t()
  def format_error(:cannot_decode_non_binary_values), do: "CBOR.decode/2 expects a binary input"

  def format_error({:duplicate_key, key}),
    do: "CBOR map contained a duplicate key (option `on_duplicate_key: :error`): #{inspect(key)}"

  def format_error({:not_well_formed, reason}), do: "CBOR input " <> not_well_formed_message(reason)

  def format_error({:invalid_tag, 24, :non_byte_string_content}),
    do: "CBOR tag 24 content was not a byte string (RFC 8949 §3.4.5.1)"

  def format_error({:invalid_tag, 24, :trailing_bytes_in_tag_24}),
    do: "CBOR tag 24 byte string had trailing bytes after the inner data item (RFC 8949 §3.4.5.1)"

  def format_error({:invalid_tag, 24, {:not_well_formed, reason}}),
    do: "CBOR tag 24 inner content was not well-formed CBOR (RFC 8949 §3.4.5.1): " <> not_well_formed_message(reason)

  def format_error({:invalid_tag, 24, inner}) when is_tuple(inner),
    do: "CBOR tag 24 inner decode failed (RFC 8949 §3.4.5.1): " <> format_error(inner)

  def format_error({:invalid_tag, tag, :non_byte_string_content}),
    do: "CBOR tag #{tag} content was not a byte string (RFC 8949 §3.4.3)"

  def format_error({:invalid_tag, tag, :not_uri_reference}),
    do: "CBOR tag #{tag} content was not a valid URI reference (RFC 8949 §3.4.5.3)"

  def format_error({:tag_decoder_raised, tag, {:raise, exception}}),
    do: "CBOR tag #{tag} decoder raised #{inspect(exception.__struct__)}: #{Exception.message(exception)}"

  def format_error({:tag_decoder_raised, tag, {:throw, payload}}),
    do: "CBOR tag #{tag} decoder threw: #{inspect(payload)}"

  def format_error({:tag_decoder_raised, tag, {:exit, payload}}),
    do: "CBOR tag #{tag} decoder exited: #{inspect(payload)}"

  def format_error({:tag_decoder_raised, tag, {:bad_return, value}}),
    do: "CBOR tag #{tag} decoder returned a non-conforming value: #{inspect(value)}"

  def format_error({:tag_decoder_failed, tag, reason}), do: "CBOR tag #{tag} decoder reported failure: #{inspect(reason)}"

  def format_error({:max_depth_exceeded, limit}), do: "CBOR nesting exceeded the configured :max_depth of #{limit}"

  # Defensive fallback for forward compatibility — if a future error reason
  # ships without a matching clause, callers still get a non-empty message
  # rather than a FunctionClauseError. Dialyzer covers the typed case via
  # the @spec above.
  def format_error(other), do: "CBOR error: #{inspect(other)}"

  defp not_well_formed_message(:malformed_header),
    do: "had a malformed initial byte (empty input or reserved additional-info value)"

  defp not_well_formed_message(:truncated), do: "ended mid-data-item (truncated)"

  defp not_well_formed_message(:malformed), do: "was not well-formed CBOR"

  defp not_well_formed_message(:indefinite_length_not_allowed),
    do: "used the indefinite-length form on a major type that disallows it (RFC 8949 App. F subkind 5)"

  defp not_well_formed_message(:stray_break_code),
    do: "contained a stray break code at a position expecting a data item (RFC 8949 App. F subkind 4)"

  defp not_well_formed_message(:nested_indefinite_string),
    do: "nested an indefinite-length string chunk inside an indefinite-length string (RFC 8949 §3.2.3)"

  defp not_well_formed_message(:reserved_simple_value_form),
    do: "used the reserved two-byte simple-value form for v < 32 (RFC 8949 §3.3)"
end
