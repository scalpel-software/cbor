# CBOR

[![Module Version](https://img.shields.io/hexpm/v/cbor.svg)](https://hex.pm/packages/cbor)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/cbor/)
[![Total Download](https://img.shields.io/hexpm/dt/cbor.svg)](https://hex.pm/packages/cbor)
[![License](https://img.shields.io/hexpm/l/cbor.svg)](https://github.com/scalpel-software/cbor/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/scalpel-software/cbor.svg)](https://github.com/scalpel-software/cbor/commits/master)

Implementation of [RFC 8949](https://www.rfc-editor.org/info/rfc8949)
[CBOR](http://cbor.io) (Concise Binary Object Representation) for Elixir.

This is a fork of [excbor](https://github.com/cabo/excbor) which modernizes
the codebase, and makes decisions on handling data types that the original library had punted on.

## Migrating from the previous version

This library is a fork of the no longer maintained excbor project.

For those migrating from previous versions of this library there are breaking changes that you should be aware of.

The module `Cbor` has been renamed to `CBOR`.

CBOR.decode will return a three item tuple of the form `{:ok, decoded, rest}`, instead of returning the decoded object. In the wild there are APIs that concat CBOR objects together. The `rest` variable includes any leftover information from the decoding operation in case you need to decode multiple objects.

Atoms will be encoded/decoded as strings, except for the special case of `:__undefined__` which has no direct translation to elixir but has semantic meaning in CBOR.

Elixir/Erlang does not have a concept of infinity, negative infinity or NaN. In order to encode or decode these values we will return a struct of the form `%CBOR.Tag{tag: :float, value: (:inf|:"-inf"|:nan)}`

If you want to encode a raw binary value, you can use the `CBOR.Tag` struct with a tag of `:bytes` and the binary as the `:value` field.

## Upgrading from 1.x to 2.0

Version 2.0 brings the library up to RFC 8949 (December 2020) and the
related ecosystem RFCs (RFC 8943, the cbor-sets-spec). The wire format is
still compatible with 7049, but encoders now produce spec-correct output
where there's a clean alternative.

### Encoder changes (wire output may differ)

* `Date` encodes as **tag 1004** (RFC 8943 full-date string), not tag 0.
  The old form was technically invalid CBOR per RFC 8949 §3.4.1.
* `MapSet` encodes as **tag 258** (cbor-sets-spec) wrapping a CBOR array,
  preserving set semantics on round-trip. Previously emitted as a bare
  array.
* Floats encode in the **shortest IEEE 754 form** (binary16/32/64) that
  exactly preserves the value (RFC 8949 §4.1). Previously always 64-bit.
* Map keys are emitted in **bytewise lexicographic order** of their
  encoded form (RFC 8949 §4.2.1) — deterministic by default.

The encoder follows §4.2.1 (map-key sort) and §4.1 (shortest float form)
but does **not** implement the §4.2.2 rule that integer-valued floats
must be encoded as integers — `CBOR.encode(1.0)` emits a binary16 float,
not the integer `1`. Callers that need byte-identical Core Deterministic
output for COSE/CWT/content-addressed use cases should encode
integer-valued floats manually as integers before calling
`CBOR.encode/1`.

### Decoder changes

* **Tag 1** (epoch-based date/time) auto-decodes to `DateTime`. Previously
  passed through as `%CBOR.Tag{tag: 1, value: ...}`. Pass
  `decode_epoch_time: false` to keep the raw integer/float.
* New built-in decoders: tag 100 (`Date`), tag 1004 (`Date`), tag 258
  (`MapSet`), tag 55799 (self-described CBOR — strip the marker).

### Reading 1.x data

The decoder remains backward-compatible with everything 1.x emitted:
tag 0 + bare-date strings still decode to `Date`, and untagged arrays
still decode to `List`.

### Maps with colliding keys

`CBOR.encode/1` now raises `ArgumentError` if two distinct Elixir keys
encode to the same wire bytes — `:foo`/`"foo"` (atoms encode as text
strings), `{1, 2}`/`[1, 2]` (tuples encode as arrays), or any custom
struct whose `defimpl CBOR.Encoder` produces a key already present.
v1.x silently emitted invalid CBOR with both keys, violating RFC 8949
§5.6. The error message names both colliding Elixir keys.

If you hit this on upgrade, the fix is at the call site — pick one
shape and stick to it. For atom-vs-string ambiguity, normalize to
strings before encoding:

```elixir
map |> Map.new(fn {k, v} -> {to_string(k), v} end) |> CBOR.encode()
```

### Minimum runtime

Elixir 1.17 and Erlang/OTP 27 are now required.

## Requirements

* Elixir 1.17 or later
* Erlang/OTP 27 or later

## Installation

```elixir
def deps do
  [
    {:cbor, "~> 2.0"}
  ]
end
```

## Usage

This library follows the standard API for CBOR libraries by exposing two methods
on the CBOR module `CBOR.encode/1` and `CBOR.decode/1`.

### Encoding

```elixir
iex(1)> CBOR.encode([1, [2, 3]])
<<130, 1, 130, 2, 3>>
```

### Decoding

```elixir
iex(2)> CBOR.decode(<<130, 1, 130, 2, 3>>)
{:ok, [1, [2, 3]], ""}
```

## Design Notes

Given that Elixir has more available data types than are supported in CBOR, decisions were made so that encoding complex data structures succeed without throwing errors. My thoughts are collected below so you can understand why encoding and decoding of a value does not necessarily return exactly the same value.

### Atoms

The only atoms that will be directly encoded are `true`, `false` `nil` and `__undefined__`. Every other atom will be converted to a string before being encoded. We surround undefined with double underscores so that you only encode an undefined value when you clearly intend to do so.

### Keyword List, Range, Tuple

These structures are converted to Lists before being encoded — CBOR has no
native representation for any of them. Round-tripping a tuple gives back
a list, etc.

### MapSet

`MapSet` round-trips via tag 258 (the [cbor-sets-spec][cbor-sets-spec])
wrapping a CBOR array. Set semantics are preserved across encode/decode.

[cbor-sets-spec]: https://github.com/input-output-hk/cbor-sets-spec

### Date

`Date` encodes as tag 1004 (RFC 8943 full-date string). The decoder also
accepts the older tag-0-with-bare-date-string form for compatibility with
data emitted by 1.x of this library.

### Time

CBOR has no IANA-registered tag for time-of-day. `Time` continues to
encode as tag 0 + ISO 8601 partial-time string — technically out-of-spec
for tag 0 (which requires a full date-time per RFC 8949 §3.4.1) but
preserves round-trip behaviour. Strict-mode decoding rejects this form.

### DateTime

Tag 0 (RFC 3339 date-time) decodes to `DateTime`. For Z-form input, the
result is in UTC. For non-Z input (e.g. `"2024-01-01T00:00:00+05:00"`),
the decoded `DateTime` carries the original offset via its `utc_offset`
and synthetic `time_zone` fields (e.g. `"+05:00"`) — round-trip through
encode produces the same wire bytes.

`DateTime.compare/2`, `DateTime.to_unix/1`, and arithmetic operations
work equivalently across both forms (same instant, different
presentation). Inter-zone conversion via `DateTime.shift_zone/2`
requires a tz database (e.g. `tzdata`); the synthetic `time_zone`
field is an ISO 8601 offset string, not an IANA zone name.

### NaiveDateTime

NaiveDateTime will be treated as if they are UTC.

### Special Values

Elixir and erlang have no concept of infinity, negative infinity and NaN. If you want to encode those values, we have a special struct `CBOR.Tag` which you can use to represent those values.

```elixir
%CBOR.Tag{tag: :float, value: :inf}

%CBOR.Tag{tag: :float, value: :"-inf"}

%CBOR.Tag{tag: :float, value: :nan}
```

`CBOR.Tag` is also useful if you want to extend `CBOR` for internal applications

## Decoder Options

`CBOR.decode/2` accepts a keyword list of options:

* `:tag_decoders` — list of modules implementing `CBOR.TagDecoder` for
  tags this library doesn't natively handle. Built-in tag numbers
  (`0`, `1`, `2`, `3`, `32`, `100`, `258`, `1004`, `55799`) are sealed —
  registering a decoder for one raises `ArgumentError` at decode time.
* `:decode_epoch_time` — `true` (default) auto-decodes tag 1 to
  `DateTime`. Set `false` to receive the raw integer/float wrapped in
  `%CBOR.Tag{tag: 1, value: ...}`.
* `:on_duplicate_key` — `:last_wins` (default), `:first_wins`, or
  `:error`. The `:error` option returns `{:error, {:duplicate_key, key}}`.
* `:max_depth` — positive integer, default `256`. Rejects inputs whose
  longest root-to-leaf chain of CBOR data items exceeds this, returning
  `{:error, {:max_depth_exceeded, limit}}`. Each container, tag wrapper,
  and primitive on the chain counts as one level. Defends against
  hostile depth-bomb input (a few-byte payload that allocates
  super-linearly).
* `:strict` — `false` (default). Set to `true` to reject not-well-formed
  CBOR (per RFC 8949 §3 and Appendix F) as typed errors. Catches
  reserved two-byte simple values, indefinite-length on major types
  0/1/6, stray break codes, nested indefinite-length string chunks,
  tag 2/3 with non-byte-string content, tag 32 with non-URI-reference
  content, and tag 24 inner content that is not exactly one well-formed
  CBOR data item (RFC 8949 §3.4.5.1).

Options are validated up front: unknown option keys, wrong-type values,
out-of-set values, and non-positive `:max_depth` raise `ArgumentError`
naming the option and its expected shape, rather than surfacing as a
misleading `{:not_well_formed, _}` decode error.

Example:

```elixir
CBOR.decode(bytes, strict: true, on_duplicate_key: :error)
```

### Rendering errors

`CBOR.format_error/1` turns a `decode_error()` term into a
human-readable string suitable for logs and operator surfaces. One
clause per typed variant, with RFC 8949 section references inline so
triagers can reach for the spec without re-parsing the reason atom.

```elixir
case CBOR.decode(bytes, strict: true) do
  {:ok, value, ""} -> value
  {:error, reason} -> Logger.warning("CBOR decode failed: " <> CBOR.format_error(reason))
end
```

The returned strings are for human consumption — don't pattern-match
on them. Wording may improve in a patch release.

## Custom Encoding

If you want to encode something that is not supported out of the box you can implement the `CBOR.Encoder` protocol for the module. You only have to implement a single `CBOR.Encoder.encode_into/2` function. An example for encoding a Money struct is given below.

```elixir
defimpl CBOR.Encoder, for: Money do
  def encode_into(money, acc) do
    money |> Money.to_string() |> CBOR.Encoder.encode_into(acc)
  end
end
```

## Custom Tag Decoding

For tags this library does not decode natively, implement
`CBOR.TagDecoder` and pass the module via `:tag_decoders`. Example for
binary UUIDs (tag 37):

```elixir
defmodule MyApp.UUIDDecoder do
  @behaviour CBOR.TagDecoder

  @impl true
  def tag_number, do: 37

  @impl true
  def decode(%CBOR.Tag{tag: :bytes, value: bytes}) when byte_size(bytes) == 16 do
    {:ok, bytes}
  end

  def decode(_), do: :error
end

CBOR.decode(bytes, tag_decoders: [MyApp.UUIDDecoder])
```

Built-in tag numbers cannot be overridden. Two user modules registering
for the same tag also raise `ArgumentError`.

### Built-in: tag 24 (Encoded CBOR data item)

Tag 24 (RFC 8949 §3.4.5.1) wraps a byte string that itself contains
CBOR. By default the library leaves it wrapped:

```elixir
%CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes, value: <inner_bytes>}}
```

Pass `CBOR.TagDecoders.EncodedCBOR` to recursively decode the inner
data item:

```elixir
CBOR.decode(bytes, tag_decoders: [CBOR.TagDecoders.EncodedCBOR])
```

The inner decode inherits the outer call's options (`:max_depth`,
`:strict`, `:on_duplicate_key`, `:tag_decoders`, `:decode_epoch_time`),
so nested tag-24 wrappers respect the outer depth budget. In strict
mode, trailing bytes or malformed inner CBOR surface as
`{:error, {:tag_decoder_failed, 24, reason}}`. Strict mode also
validates the inner content even *without* this decoder registered,
in which case errors surface as `{:error, {:invalid_tag, 24, reason}}`
and the success-path result stays wrapped (strict validates without
auto-unwrapping — opt into `EncodedCBOR` for the unwrap).

### Why are built-in tags sealed?

Tags `0`, `1`, `2`, `3`, `32`, `100`, `258`, `1004`, and `55799` have
RFC-defined semantics (`RFC 8949` §3.4 + RFC 8943 + cbor-sets-spec).
Allowing user code to override them would create interop hazards: the
same wire bytes would decode differently in different applications.
The library raises `ArgumentError` at registration to surface the
collision at the source rather than in production.

If you need custom handling for one of these tag numbers — for
example, consuming non-conforming wire data from a legacy peer — there
are two paths:

1. **Decode normally and post-process.** The library falls back to
   `%CBOR.Tag{tag: N, value: <content>}` whenever content fails
   built-in validation (e.g. tag 1 with a string instead of an epoch
   number, tag 2 with non-byte-string content). Pattern-match on the
   wrap and apply the legacy interpretation in your consumer.
2. **Use a non-built-in tag for your own data.** CBOR's tag namespace
   is `uint64`; pick something outside the IANA-registered range and
   `CBOR.TagDecoder` gives you full control.

## API stability

This library follows [Semantic Versioning](https://semver.org). Within
a 2.x line:

**Stable**:

- The shape of `decode_error()` — variants will not be removed or
  renamed. New variants may be added; pattern-matching consumers
  should include a default clause.
- The exception classes `CBOR.encode/1` raises (`Protocol.UndefinedError`,
  `ArgumentError`), as documented in its docstring.

**Not stable**:

- Strings returned by `CBOR.format_error/1` are for human consumption.
  Don't pattern-match on them — wording may improve in a patch release.
- Specific reasons within the strict-mode "documented partial-coverage
  gaps". Inputs currently surfacing as `:malformed_header` /
  `:malformed` / `:truncated` (BEAM-class catch-alls translated by the
  public rescue) may reclassify to typed `{:invalid_tag, _, _}` or
  more specific `{:not_well_formed, _}` reasons in a future minor as
  strict-mode coverage grows. The fence tests in `options_test.exs`
  under `"strict option (documented partial-coverage gaps)"` pin the
  current boundary; treat the catch-alls as non-final classifications.
- Encoder wire output may shift if RFC 8949 §4.2.2 (Core Deterministic
  integer-valued floats as integers) is later implemented. Decoded
  values still round-trip, but byte-for-byte equivalence with a prior
  release is not promised.

### Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/cbor](https://hexdocs.pm/cbor).


## Copyright and License

Copyright (c) 2019-2026 Thomas Cioppettini

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
