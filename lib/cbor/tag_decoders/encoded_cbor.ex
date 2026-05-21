defmodule CBOR.TagDecoders.EncodedCBOR do
  @moduledoc """
  Built-in `CBOR.TagDecoder` for tag 24 (Encoded CBOR data item,
  RFC 8949 §3.4.5.1). Recursively decodes the wrapped byte string
  as a single CBOR data item.

  ## Usage

      CBOR.decode(binary, tag_decoders: [CBOR.TagDecoders.EncodedCBOR])

  Without this decoder registered, tag 24 decodes to the wrapped form
  `%CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes, value: <bytes>}}`
  and consumers must call `CBOR.decode/1` on the inner bytes themselves.

  ## Option propagation

  When invoked from `CBOR.decode/2`, the inner decode inherits the
  outer call's options — `:max_depth` (with the depth already consumed
  on the outer side subtracted from the budget), `:strict`,
  `:tag_decoders` (so nested tag-24 wrappers also unwrap),
  `:on_duplicate_key`, and `:decode_epoch_time`. This closes the
  depth-bypass that an unconfigured recursive decoder would otherwise
  introduce.

  Calling `CBOR.TagDecoders.EncodedCBOR.decode/1` directly (outside
  `CBOR.decode/2`) runs the inner decode with default options.

  ## Strict mode

  In strict mode (`strict: true`), a tag-24 byte string with trailing
  bytes after the inner data item, or whose inner content fails to
  decode, surfaces as
  `{:error, {:tag_decoder_failed, 24, reason}}` per RFC 8949 §3.4.5.1
  (the byte string MUST contain exactly one well-formed CBOR data
  item). In lenient mode (default), the same inputs fall back to the
  wrapped form `%CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes, value: bytes}}`.
  """

  @behaviour CBOR.TagDecoder

  @impl true
  def tag_number, do: 24

  @impl true
  @doc """
  Convenience entry point equivalent to `decode(value, [])`. Used by
  `CBOR.decode/2` when no per-call options need to be threaded; runs
  the inner decode with default options.
  """
  def decode(value), do: decode(value, [])

  @impl true
  def decode(%CBOR.Tag{tag: :bytes, value: bytes}, opts) when is_binary(bytes) do
    case CBOR.decode(bytes, opts) do
      {:ok, value, <<>>} -> {:ok, value}
      {:ok, _value, _trailing} -> maybe_strict_error(opts, :trailing_bytes_in_tag_24)
      {:error, reason} -> maybe_strict_error(opts, reason)
    end
  end

  def decode(_, _), do: :error

  defp maybe_strict_error(opts, reason) do
    if Keyword.get(opts, :strict, false), do: {:error, reason}, else: :error
  end
end
