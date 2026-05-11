# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0-rc.1]

This release brings the library up to RFC 8949 (December 2020) and the
related ecosystem RFCs (RFC 8943, the cbor-sets-spec). RFC 8949 keeps the
wire format compatible with 7049 but tightens validity rules and redefines
deterministic encoding. The encoder now produces spec-correct output where
there's a clean alternative; the decoder gains a strict mode and a
plug-in registry for user-supplied tag handlers.

### Breaking changes

- **`Date` encodes as tag 1004** (RFC 8943 full-date string), not tag 0 +
  bare-date string. The old form was technically invalid CBOR per RFC 8949
  §3.4.1. The decoder still accepts the old form for compatibility with
  v1.x-emitted data.
- **`MapSet` encodes as tag 258** (cbor-sets-spec) wrapping a CBOR array,
  not as a bare array. Set semantics now round-trip.
- **Tag 1 (epoch-based date/time) auto-decodes to `DateTime`**, instead of
  passing through as `%CBOR.Tag{tag: 1, value: integer | float}`. Set
  `decode_epoch_time: false` on `CBOR.decode/2` to keep the previous
  behaviour.
- **Floats encode in shortest IEEE 754 form** (binary16 / binary32 /
  binary64), per RFC 8949 §4.1 preferred serialization. Previously always
  64-bit. Wire bytes change for many floats; decoded values are identical.
- **Map keys are emitted in bytewise-lex sorted order** (RFC 8949 §4.2.1)
  unconditionally. Wire output is now deterministic for a given map.
- **Minimum runtime requirements**: Elixir 1.17, Erlang/OTP 27.
- **`CBOR.encode/1` now raises `ArgumentError` on maps whose keys collide
  on the wire.** Previously, encoding `%{:foo => 1, "foo" => 2}` silently
  emitted invalid CBOR with two `"foo"` keys, violating RFC 8949 §5.6.
  Atoms encode as text strings, tuples and ranges as arrays, so distinct
  Elixir terms can produce identical encoded keys. The encoder now
  detects this after deterministic sort and refuses rather than emitting
  a malformed map.
- **Two-byte simple-value form for v < 32 is rejected in lenient mode
  for v in 24..31** and **normalized for v in 20..23** to match the
  canonical single-byte form's decoded values (`false`, `true`, `nil`,
  `:__undefined__`). v1.x accepted `<<0xF8, v>>` for any v < 32 as
  `%CBOR.Tag{tag: :simple, value: v}`. The wire form is malformed per
  RFC 8949 §3.3 (Appendix F subkind 2); the v1.x acceptance produced
  terms that didn't round-trip through the encoder. Strict mode
  rejection unchanged. v < 20 still wraps as
  `%CBOR.Tag{tag: :simple, value: v}` — the canonical single-byte form
  decodes the same way, so the round-trip is a fixed point.
- **Tag 2/3 (bignum) with non-byte-string content now wraps in lenient
  mode** instead of silently coercing the bytes into an integer.
  RFC 8949 §3.4.3 requires byte-string content; v1.x reinterpreted
  text-string bytes as the bignum payload (`<<0xC2, 0x68, "ABCDEFGH">>`
  decoded to `4_702_111_234_474_983_745`), a type-confusion path.
  Strict mode already returned
  `{:error, {:invalid_tag, 2 | 3, :non_byte_string_content}}`; lenient
  now returns `%CBOR.Tag{tag: 2, value: "ABCDEFGH"}` so callers can
  detect the wire-form error. The library's own encoder always wraps
  bignum payload as a byte string, so no library-emitted CBOR
  round-trip is affected — only hand-crafted bytes or non-conforming
  peer input.
- **Decode error atoms renamed.** The `:cbor_function_clause_error`,
  `:cbor_match_error`, and `:cbor_case_clause_error` reasons returned
  by `CBOR.decode/2` for malformed input have been replaced by typed
  `{:not_well_formed, reason}` tuples joining the existing strict-mode
  error family. Reasons: `:malformed_header` (was `FunctionClauseError`),
  `:truncated` (was `MatchError`), `:malformed` (was `CaseClauseError`).
  The old atoms named BEAM exception classes — internal refactors
  changed which fired for which input. Pattern-match consumers must
  update.

### Added

- `CBOR.format_error/1` — renders a `decode_error()` term as a
  human-readable string for logging, error reporting, or operator
  surfaces. One clause per typed variant plus a defensive fallback
  for forward compatibility. Strings reference the relevant RFC 8949
  section so triagers can reach for the spec without re-parsing the
  reason atom.
- README "API stability" section commits: `decode_error()` variant
  shapes are stable across 2.x (additions allowed); BEAM-class
  catch-alls (`:malformed_header`/`:malformed`/`:truncated`) may
  reclassify to typed reasons as strict-mode coverage grows;
  `format_error/1` strings are explicitly not stable.
- README "Why are built-in tags sealed?" section documents the
  rationale (RFC-defined semantics + interop hazards) and the
  practical escape hatches for callers needing custom handling
  of one of the sealed tag numbers.
- `CBOR.decode/2` accepts options.
- New `CBOR.TagDecoder` behaviour for plugging in user-supplied decoders
  for tags this library does not natively handle. Built-in tag numbers
  (`0`, `1`, `2`, `3`, `32`, `100`, `258`, `1004`, `55799`) are sealed —
  registering a decoder for one raises `ArgumentError`. Two user modules
  registering for the same non-built-in tag also raise.
- Decoder options:
  - `:tag_decoders` — list of `CBOR.TagDecoder` modules.
  - `:decode_epoch_time` — opt out of tag 1 → `DateTime` auto-decoding.
  - `:on_duplicate_key` — `:last_wins` (default), `:first_wins`, or
    `:error`. The `:error` policy returns `{:error, {:duplicate_key, key}}`.
    The check operates on *decoded* Elixir terms, not encoded bytes, so
    wire-distinct CBOR keys that decode to the same Elixir term will
    trip it: tag 0 + ISO date string and tag 1004 + same date both
    decode to `Date`; integer 5 and tag 2 wrapping `<<5>>` both decode
    to `5`. The wire is RFC 8949-valid (distinct encoded keys per §5.6)
    but the decoded map carries the same key twice.
  - `:strict` — reject not-well-formed CBOR as typed errors per RFC 8949
    §3 and Appendix F. **Partial coverage** — explicitly handles:
    indefinite-length on major types 0/1/6/7 (App. F subkind 5),
    nested indefinite-length string chunks (subkind 5), stray break
    codes (subkind 4), reserved two-byte simple values v < 32
    (subkind 1), tag 2/3 with non-byte-string content, tag 32
    with non-URI-reference content, and **tag 24 inner well-formedness
    (§3.4.5.1) — the wrapped byte string MUST contain exactly one
    well-formed CBOR data item**. Tag 24 strict validation fires whether
    or not the caller registered `CBOR.TagDecoders.EncodedCBOR`: with
    the decoder registered, errors surface as
    `{:tag_decoder_failed, 24, reason}`; without, as
    `{:invalid_tag, 24, reason}` (the success-path shape stays wrapped
    — strict mode validates without auto-unwrapping). Other subkinds
    (non-preferred integer encodings, reserved additional-info 28-30,
    tag 0 with non-string content) currently surface as the generic
    `{:not_well_formed, :malformed | :malformed_header | :truncated}`
    family rather than typed strict-mode reasons.
  - `:max_depth` — reject inputs whose longest root-to-leaf chain of
    CBOR data items exceeds this. Default `256`. Returns
    `{:error, {:max_depth_exceeded, limit}}` on overflow. Each
    container, tag wrapper, and primitive on the chain counts as one
    level. Protects against stack/heap exhaustion from hostile input.
  - **Decoder options are validated up front and raise `ArgumentError`
    on caller-bug input** — unknown option keys (typo'd
    `on_duplicate_keys: :error`), wrong-type values
    (`strict: "yes"`), out-of-set values (`on_duplicate_key: :bogus`),
    and non-positive `:max_depth` all raise with a message naming the
    option and its expected shape. Previously, value-typos surfaced as
    the misleading `{:error, {:not_well_formed, :malformed_header}}`
    (the bad value reached an inner clause that had no match, the
    resulting `FunctionClauseError` was caught by the public rescue,
    and labelled as if the *bytes* were malformed); name-typos were
    silently ignored. Caller bugs are now loud, not silent.
- New built-in tag decoders: tag 1 (epoch time → `DateTime`), tag 100
  (days since epoch → `Date`), tag 258 (set → `MapSet`), tag 1004
  (full-date → `Date`), tag 55799 (self-described CBOR — strip the marker).
- Opt-in `CBOR.TagDecoders.EncodedCBOR` for tag 24 (Encoded CBOR data
  item, RFC 8949 §3.4.5.1). Pass via
  `CBOR.decode(bin, tag_decoders: [CBOR.TagDecoders.EncodedCBOR])` to
  recursively decode the wrapped byte string. The inner decode
  inherits the outer call's options (`:max_depth`, `:strict`,
  `:tag_decoders`, `:on_duplicate_key`, `:decode_epoch_time`) so
  nested tag-24 wrappers respect the outer depth budget. In strict
  mode, trailing bytes or malformed inner CBOR surface as
  `{:error, {:tag_decoder_failed, 24, reason}}` rather than silently
  falling back to the wrapped form.
- Optional `CBOR.TagDecoder.decode/2` callback. Decoders that re-enter
  `CBOR.decode/2` should implement this form to receive the outer
  call's options snapshot and pass it through. `decode/1` remains
  supported for non-reentrant decoders. The library prefers `decode/2`
  when both are exported.
- `{:error, {:tag_decoder_raised, tag, reason}}` — when a custom
  `CBOR.TagDecoder` raises, throws, exits, or returns a non-conforming
  shape, the decoder produces this typed error. `reason` is uniformly a
  2-tuple: `{:raise, exception}`, `{:throw, payload}`,
  `{:exit, payload}`, or `{:bad_return, value}`.
- `{:error, {:tag_decoder_failed, tag, reason}}` — when a `CBOR.TagDecoder`
  returns `{:error, reason}` (a new return shape, distinct from `:error`),
  the library bubbles that as this typed error rather than falling back
  to the wrapped `%CBOR.Tag{}` form. Use it for unambiguous spec
  violations the caller should know about. `EncodedCBOR` uses this in
  strict mode for trailing bytes or malformed inner CBOR.

### Compatibility notes

- The decoder remains backward-compatible with data emitted by v1.x:
  - Tag 0 + bare date string still decodes to `Date`.
  - Tag 0 + bare time string still decodes to `Time` (the v2 encoder also
    still emits this form for `Time`, since CBOR has no IANA-registered
    time-of-day tag yet).
  - Untagged arrays still decode to `List`.
- Strict mode (`strict: true`) rejects all of the above as invalid per
  RFC 8949, which is correct strict behaviour.
- **`Time` round-trips through tag 0** (with a bare RFC 3339 partial-time
  string), which is technically out-of-spec for tag 0 — RFC 8949 §3.4.1
  expects a full date-time. Strict-mode decode rejects this, so
  `CBOR.encode(t) |> CBOR.decode(strict: true)` fails on `Time` values
  this library produced. Callers using strict mode should encode `Time`
  manually as a plain text string. The encoder will move to a registered
  IANA tag once one is assigned for time-of-day; see `specs/TIME-OF-DAY.md`.
- **Tag 0 round-trip preserves the time-offset on the wire.** v1.x
  silently normalized non-Z offsets to UTC on decode
  (`"2024-01-01T00:00:00+05:00"` → `~U[2023-12-31 19:00:00Z]`), losing
  wire-form information. v2.0 constructs a non-UTC `DateTime` for non-Z
  input — the wall clock and `utc_offset` reflect the original offset,
  and re-encoding produces the same wire bytes. Z-form input is
  unchanged. The synthetic `time_zone` field uses an ISO 8601 offset
  string (e.g. `"+05:00"`); inter-zone conversion still requires
  `tzdata`, but `DateTime.compare/2`, `DateTime.to_unix/1`, and
  arithmetic all work without it. The one residual asymmetry: input
  `"…+00:00"` decodes via `DateTime.from_iso8601/1`'s offset-zero path
  and re-encodes as `Z` (RFC 3339 treats the two as equivalent).

### Lossy round-trips

- **NaN payload is not preserved.** All NaN bit patterns (signaling vs
  quiet, specific mantissa bits) decode to `%CBOR.Tag{tag: :float, value:
  :nan}`. Re-encoding emits canonical quiet NaN `0xF9 0x7E 0x00`. Peers
  that pin a specific NaN payload (rare outside test vectors) won't
  round-trip through this library.
- **Atoms encode as text strings.** `:foo` encodes the same as `"foo"` and
  decodes to `"foo"`. Only `true`, `false`, `nil`, and `:__undefined__`
  retain atom-ness across round-trip.

### Determinism scope

The encoder implements RFC 8949 §4.2.1 (map-key bytewise-lex sort) and
§4.1 preferred serialization for floats (shortest IEEE 754 form). It
does **not** implement the additional §4.2.2 rule that integer-valued
floats must be encoded as integers — `CBOR.encode(1.0)` emits `0xF9
0x3C 0x00` (binary16), not `0x01`. This preserves float-ness across
round-trip but means the wire output is **not** byte-identical to a
fully Core-Deterministic peer (COSE, CWT, content-addressed stores).
Callers that need byte-identical Core Deterministic output should
encode integer-valued floats manually as integers before calling
`CBOR.encode/1`.

### Implementation notes

- Decoder context (`:tag_decoders`, `:decode_epoch_time`,
  `:on_duplicate_key`, `:strict`) is threaded through every recursive call
  so options apply at any nesting depth.
- `:max_depth` is a **quota**, not a stack-headroom defense. Empirical
  measurement on OTP 27 / Elixir 1.19 shows the BEAM successfully
  decodes 4M+ levels of nested arrays without a stack crash (~400 ns
  per level, linear scaling). The default `:max_depth: 256` therefore
  sits ~16,000× below the practical ceiling — generous for realistic
  CBOR (typical nesting < 16 levels) while bounding the super-linear
  allocation pressure an attacker could exploit with a tiny depth-bomb
  input.

## [1.0.2] - 2023-02-14

- Bump patch version to handle potential `CaseClauseError` from the
  decoder.

## [1.0.1] - 2023-02-14

- Add a test for the recently added `MatchError`.

## [1.0.0] - earlier

Initial release as a fork of [excbor](https://github.com/cabo/excbor).
Module renamed `Cbor` → `CBOR`. `CBOR.decode/1` returns
`{:ok, decoded, rest}`. Atoms encode as strings (except `nil`, `true`,
`false`, `:__undefined__`). Special floats (`inf`, `-inf`, `nan`)
represented via `%CBOR.Tag{tag: :float, value: ...}`.
