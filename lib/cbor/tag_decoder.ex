defmodule CBOR.TagDecoder do
  @moduledoc """
  Behaviour for decoding CBOR tags this library does not natively handle.

  Built-in tags (`0`, `1`, `2`, `3`, `32`, `100`, `258`, `1004`, `55799`)
  are sealed and cannot be overridden. A module whose `tag_number/0`
  returns a built-in number causes `CBOR.decode/2` to raise
  `ArgumentError` at the start of decoding.

  Two user modules registering for the same non-built-in tag also raise
  `ArgumentError` — silent shadowing across deps would be hard to debug.

  ## Example

      defmodule MyApp.UUIDDecoder do
        @behaviour CBOR.TagDecoder

        @impl true
        def tag_number, do: 37

        @impl true
        def decode(%CBOR.Tag{tag: :bytes, value: bytes})
            when byte_size(bytes) == 16 do
          {:ok, bytes}
        end

        def decode(_), do: :error
      end

      CBOR.decode(bin, tag_decoders: [MyApp.UUIDDecoder])

  ## Built-in opt-in decoders

  `CBOR.TagDecoders.EncodedCBOR` ships as a first-party `CBOR.TagDecoder`
  for tag 24 (Encoded CBOR data item, RFC 8949 §3.4.5.1). Register it
  the same way:

      CBOR.decode(bin, tag_decoders: [CBOR.TagDecoders.EncodedCBOR])
  """

  @doc """
  The CBOR tag number this module decodes. Must NOT be a built-in tag
  number; the library raises `ArgumentError` if it is.
  """
  @callback tag_number() :: non_neg_integer()

  @doc """
  Decode the inner value of a tag. The inner value has already been
  decoded as a CBOR data item by the time this callback runs.

  Return:

    * `{:ok, term}` — substitute `term` as the decoded value for the tag.
    * `:error` — the inner value is invalid for this tag. The library
      falls back to `%CBOR.Tag{tag: N, value: inner}` in lenient mode
      (default).
    * `{:error, reason}` — the inner content is invalid in a way the
      caller should know about. The library returns
      `{:error, {:tag_decoder_failed, tag, reason}}` rather than falling
      back to `%CBOR.Tag{}`. Use this when the spec violation is
      unambiguous (e.g. `CBOR.TagDecoders.EncodedCBOR` in strict mode for
      trailing bytes or malformed inner CBOR). Prefer plain `:error`
      for "this isn't my tag" rejections that should fall through.

  Raising, throwing, exiting, or returning any other shape causes the
  surrounding `CBOR.decode/2` call to return
  `{:error, {:tag_decoder_raised, tag, reason}}` rather than propagating
  the exception. The `reason` is one of:

    * `{:raise, exception_struct}` — `decode/1` raised an Elixir exception.
    * `{:throw, payload}` — `decode/1` called `throw/1`.
    * `{:exit, payload}` — `decode/1` called `exit/1`.
    * `{:bad_return, value}` — `decode/1` returned a value that's neither
      `{:ok, _}`, `:error`, nor `{:error, _}`.

  Implementations should prefer returning `:error` or `{:error, _}` over
  raising.
  """
  @callback decode(value :: term()) :: {:ok, term()} | {:error, term()} | :error

  @doc """
  Optional reentrant form of `decode/1`. Receives the same `value` plus a
  keyword-list snapshot of the outer `CBOR.decode/2` options
  (`:max_depth` reduced by the depth already consumed, `:strict`,
  `:on_duplicate_key`, `:decode_epoch_time`, `:tag_decoders`).

  Decoders that re-enter `CBOR.decode/2` on a sub-payload should
  implement this form and pass `opts` through, so the inner decode
  inherits the outer call's depth budget and strictness.
  `CBOR.TagDecoders.EncodedCBOR` is the canonical example.

  When both `decode/1` and `decode/2` are exported, the library prefers
  `decode/2`. At least one of the two must be implemented.
  """
  @callback decode(value :: term(), opts :: keyword()) :: {:ok, term()} | {:error, term()} | :error

  @optional_callbacks decode: 1, decode: 2
end
