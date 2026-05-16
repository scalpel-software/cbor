defmodule CBOR.Decoder do
  @moduledoc false

  alias CBOR.TagDecoders.EncodedCBOR

  @builtin_tags [0, 1, 2, 3, 32, 100, 258, 1004, 55_799]
  @valid_decode_options [:tag_decoders, :decode_epoch_time, :on_duplicate_key, :strict, :max_depth]
  @valid_on_duplicate_key [:last_wins, :first_wins, :error]

  def decode(binary), do: decode(binary, [])

  def decode(binary, opts) when is_list(opts) do
    ctx = build_context(opts)
    decode_value(binary, ctx)
  end

  defp build_context(opts) do
    validate_decode_options!(opts)

    %{
      tag_decoders: build_decoder_map(Keyword.get(opts, :tag_decoders, [])),
      decode_epoch_time: Keyword.get(opts, :decode_epoch_time, true),
      on_duplicate_key: Keyword.get(opts, :on_duplicate_key, :last_wins),
      strict: Keyword.get(opts, :strict, false),
      max_depth: Keyword.get(opts, :max_depth, 256),
      depth: 0
    }
  end

  # Validates option *names* and *value types/shapes*. Caller-bug failures
  # (typo in key name, wrong-type value) raise `ArgumentError` rather than
  # surfacing as the misleading `{:error, {:not_well_formed, :malformed_header}}`
  # they used to: `put_with_policy/4` and similar inner clauses had no
  # match for invalid values, the resulting `FunctionClauseError` was caught
  # by the public rescue in `cbor.ex`, and labelled as if the *bytes* were
  # malformed. The deeper content of `:tag_decoders` (modules implement the
  # behaviour, no built-in / duplicate registrations) is still validated by
  # `build_decoder_map/1` because that check needs the constructed map.
  defp validate_decode_options!(opts) do
    Enum.each(opts, &validate_decode_option!/1)
  end

  defp validate_decode_option!({:tag_decoders, v}) do
    check!(:tag_decoders, v, &is_list/1, "a list of CBOR.TagDecoder modules")
  end

  defp validate_decode_option!({:decode_epoch_time, v}) do
    check!(:decode_epoch_time, v, &is_boolean/1, "a boolean")
  end

  defp validate_decode_option!({:on_duplicate_key, v}) do
    check!(
      :on_duplicate_key,
      v,
      &(&1 in @valid_on_duplicate_key),
      "one of #{inspect(@valid_on_duplicate_key)}"
    )
  end

  defp validate_decode_option!({:strict, v}) do
    check!(:strict, v, &is_boolean/1, "a boolean")
  end

  defp validate_decode_option!({:max_depth, v}) do
    check!(:max_depth, v, &(is_integer(&1) and &1 >= 1), "a positive integer (>= 1)")
  end

  defp validate_decode_option!({key, _v}) when is_atom(key) do
    raise ArgumentError,
          "unknown CBOR.decode option: #{inspect(key)}. Valid options: #{inspect(@valid_decode_options)}"
  end

  defp validate_decode_option!(other) do
    raise ArgumentError,
          "CBOR.decode options must be a keyword list of {atom, value} pairs, got entry: #{inspect(other)}"
  end

  defp check!(name, value, pred, expected) do
    if pred.(value) do
      :ok
    else
      raise ArgumentError,
            "CBOR.decode option #{inspect(name)} must be #{expected}, got: #{inspect(value)}"
    end
  end

  defp build_decoder_map(modules) do
    Enum.reduce(modules, %{}, &add_decoder!/2)
  end

  defp add_decoder!(mod, acc) do
    validate_not_builtin(mod)
    validate_implements_decode(mod)
    tag = mod.tag_number()

    case acc do
      %{^tag => _} -> raise ArgumentError, "multiple decoders conflict on tag #{tag}"
      _ -> Map.put(acc, tag, mod)
    end
  end

  defp validate_not_builtin(mod) do
    tag = mod.tag_number()

    if tag in @builtin_tags do
      raise ArgumentError,
            "tag #{tag} is built-in to cbor and cannot be overridden by #{inspect(mod)}"
    end
  end

  defp validate_implements_decode(mod) do
    if !(function_exported?(mod, :decode, 1) or function_exported?(mod, :decode, 2)) do
      raise ArgumentError,
            "tag decoder #{inspect(mod)} must implement decode/1 or decode/2"
    end
  end

  defp decode_value(_binary, %{depth: d, max_depth: m}) when d >= m do
    throw({:cbor_max_depth_exceeded, m})
  end

  defp decode_value(binary, ctx) do
    ctx = %{ctx | depth: ctx.depth + 1}
    decode_value(binary, header(binary), ctx)
  end

  # Strict mode: indefinite-length on major types 0/1/6 is not well-formed
  # (RFC 8949 Appendix F subkind 5). Lenient mode falls through to a
  # CaseClauseError (preserved for backward compatibility).
  defp decode_value(_binary, {mt, :indefinite, _rest}, %{strict: true}) when mt in [0, 1, 6] do
    throw({:cbor_not_well_formed, :indefinite_length_not_allowed})
  end

  # Strict mode: a stray break code (mt 7 + additional info 31) at a
  # position that expects a data item is not well-formed (App. F subkind 4).
  defp decode_value(_binary, {7, :indefinite, _rest}, %{strict: true}) do
    throw({:cbor_not_well_formed, :stray_break_code})
  end

  defp decode_value(_binary, {mt, :indefinite, rest}, ctx) do
    case mt do
      2 -> mark_as_bytes(decode_string_indefinite(rest, 2, []))
      3 -> decode_string_indefinite(rest, 3, [])
      4 -> decode_array_indefinite(rest, ctx, [])
      5 -> decode_map_indefinite(rest, ctx, %{})
    end
  end

  defp decode_value(bin, {mt, value, rest}, ctx) do
    case mt do
      0 -> {value, rest}
      1 -> {-value - 1, rest}
      2 -> mark_as_bytes(decode_string(rest, value))
      3 -> decode_string(rest, value)
      4 -> decode_array(value, rest, ctx)
      5 -> decode_map(value, rest, ctx)
      6 -> decode_other(value, decode_value(rest, ctx), ctx)
      7 -> decode_float(bin, value, rest, ctx)
    end
  end

  defp header(<<mt::size(3), val::size(5), rest::binary>>) when val < 24 do
    {mt, val, rest}
  end

  defp header(<<mt::size(3), 24::size(5), val::size(8), rest::binary>>) do
    {mt, val, rest}
  end

  defp header(<<mt::size(3), 25::size(5), val::size(16), rest::binary>>) do
    {mt, val, rest}
  end

  defp header(<<mt::size(3), 26::size(5), val::size(32), rest::binary>>) do
    {mt, val, rest}
  end

  defp header(<<mt::size(3), 27::size(5), val::size(64), rest::binary>>) do
    {mt, val, rest}
  end

  defp header(<<mt::size(3), 31::size(5), rest::binary>>) do
    {mt, :indefinite, rest}
  end

  defp decode_string(rest, len) do
    <<value::binary-size(^len), new_rest::binary>> = rest
    {value, new_rest}
  end

  defp decode_string_indefinite(rest, actmt, acc) do
    case header(rest) do
      {7, :indefinite, new_rest} ->
        {Enum.join(Enum.reverse(acc)), new_rest}

      # RFC 8949 §3.2.3 / Appendix F subkind 5: chunks inside an
      # indefinite-length string must themselves be definite-length.
      {^actmt, :indefinite, _new_rest} ->
        throw({:cbor_not_well_formed, :nested_indefinite_string})

      {^actmt, len, mid_rest} when is_integer(len) ->
        <<value::binary-size(^len), new_rest::binary>> = mid_rest
        decode_string_indefinite(new_rest, actmt, [value | acc])
    end
  end

  defp mark_as_bytes({x, rest}), do: {%CBOR.Tag{tag: :bytes, value: x}, rest}

  defp decode_array(0, rest, _ctx), do: {[], rest}
  defp decode_array(len, rest, ctx), do: decode_array(len, [], rest, ctx)
  defp decode_array(0, acc, bin, _ctx), do: {Enum.reverse(acc), bin}

  defp decode_array(len, acc, bin, ctx) do
    {value, bin_rest} = decode_value(bin, ctx)
    decode_array(len - 1, [value | acc], bin_rest, ctx)
  end

  defp decode_array_indefinite(<<0xFF, new_rest::binary>>, _ctx, acc) do
    {Enum.reverse(acc), new_rest}
  end

  defp decode_array_indefinite(rest, ctx, acc) do
    {value, new_rest} = decode_value(rest, ctx)
    decode_array_indefinite(new_rest, ctx, [value | acc])
  end

  defp decode_map(0, rest, _ctx), do: {%{}, rest}
  defp decode_map(len, rest, ctx), do: decode_map(len, %{}, rest, ctx)
  defp decode_map(0, acc, bin, _ctx), do: {acc, bin}

  defp decode_map(len, acc, bin, ctx) do
    {key, key_rest} = decode_value(bin, ctx)
    {value, bin_rest} = decode_value(key_rest, ctx)
    acc = put_with_policy(acc, key, value, ctx.on_duplicate_key)
    decode_map(len - 1, acc, bin_rest, ctx)
  end

  defp decode_map_indefinite(<<0xFF, new_rest::binary>>, _ctx, acc), do: {acc, new_rest}

  defp decode_map_indefinite(rest, ctx, acc) do
    {key, key_rest} = decode_value(rest, ctx)
    {value, new_rest} = decode_value(key_rest, ctx)
    acc = put_with_policy(acc, key, value, ctx.on_duplicate_key)
    decode_map_indefinite(new_rest, ctx, acc)
  end

  defp put_with_policy(acc, key, value, :last_wins), do: Map.put(acc, key, value)
  defp put_with_policy(acc, key, value, :first_wins), do: Map.put_new(acc, key, value)

  defp put_with_policy(acc, key, value, :error) do
    if Map.has_key?(acc, key) do
      throw({:cbor_duplicate_key, key})
    else
      Map.put(acc, key, value)
    end
  end

  defp decode_float(<<0xF4, _::binary>>, _value, rest, _ctx), do: {false, rest}
  defp decode_float(<<0xF5, _::binary>>, _value, rest, _ctx), do: {true, rest}
  defp decode_float(<<0xF6, _::binary>>, _value, rest, _ctx), do: {nil, rest}
  defp decode_float(<<0xF7, _::binary>>, _value, rest, _ctx), do: {:__undefined__, rest}

  defp decode_float(<<0xF9, sign::size(1), exp::size(5), mant::size(10), _::binary>>, _value, rest, _ctx) do
    {decode_half(sign, exp, mant), rest}
  end

  defp decode_float(<<0xFA, value::float-size(32), _::binary>>, _v, rest, _ctx) do
    {value, rest}
  end

  defp decode_float(<<0xFA, sign::size(1), 255::size(8), mant::size(23), _::binary>>, _v, rest, _ctx) do
    {decode_non_finite(sign, mant), rest}
  end

  defp decode_float(<<0xFB, value::float, _::binary>>, _v, rest, _ctx) do
    {value, rest}
  end

  defp decode_float(<<0xFB, sign::size(1), 2047::size(11), mant::size(52), _::binary>>, _v, rest, _ctx) do
    {decode_non_finite(sign, mant), rest}
  end

  # Two-byte simple value with v < 32 — not well-formed per RFC 8949 §3.3.
  # Strict mode rejects.
  defp decode_float(<<0xF8, v::8, _::binary>>, _value, _rest, %{strict: true}) when v < 32 do
    throw({:cbor_not_well_formed, :reserved_simple_value_form})
  end

  # Lenient: v in 24..31 has no canonical single-byte form (those values are
  # truly unrepresentable per §3.3) and the encoder raises `ArgumentError` if
  # asked to emit them. Reject to keep the encode∘decode round-trip clean —
  # wrapping would produce a term the encoder cannot serialize.
  defp decode_float(<<0xF8, v::8, _::binary>>, _value, _rest, _ctx) when v in 24..31 do
    throw({:cbor_not_well_formed, :reserved_simple_value_form})
  end

  # Lenient: v in 20..23 — normalize to the same Elixir terms the canonical
  # single-byte form decodes to (false / true / null / undefined). Re-encode
  # produces the canonical bytes that round-trip cleanly.
  defp decode_float(<<0xF8, 20, _::binary>>, _value, rest, _ctx), do: {false, rest}
  defp decode_float(<<0xF8, 21, _::binary>>, _value, rest, _ctx), do: {true, rest}
  defp decode_float(<<0xF8, 22, _::binary>>, _value, rest, _ctx), do: {nil, rest}
  defp decode_float(<<0xF8, 23, _::binary>>, _value, rest, _ctx), do: {:__undefined__, rest}

  # Lenient: v < 20 — wrap in `%CBOR.Tag{tag: :simple, value: v}`. Re-encoding
  # uses the canonical single-byte form (`<<0xE0 | v>>`), which round-trips
  # back to the same wrapped term.
  defp decode_float(<<0xF8, v::8, _::binary>>, _value, rest, _ctx) when v < 20 do
    {%CBOR.Tag{tag: :simple, value: v}, rest}
  end

  defp decode_float(_bin, value, rest, _ctx) do
    {%CBOR.Tag{tag: :simple, value: value}, rest}
  end

  defp decode_other(value, {inner, rest}, ctx), do: {decode_tag(value, inner, ctx), rest}

  defp decode_non_finite(0, 0), do: %CBOR.Tag{tag: :float, value: :inf}
  defp decode_non_finite(1, 0), do: %CBOR.Tag{tag: :float, value: :"-inf"}
  defp decode_non_finite(_, _), do: %CBOR.Tag{tag: :float, value: :nan}

  defp decode_half(sign, 31, mant), do: decode_non_finite(sign, mant)

  # 2**112 -- difference in bias
  defp decode_half(sign, exp, mant) do
    <<value::float-size(32)>> = <<sign::size(1), exp::size(8), mant::size(10), 0::size(13)>>
    value * 5_192_296_858_534_827_628_530_496_329_220_096.0
  end

  defp decode_tag(0, value, _ctx), do: decode_datetime(value)

  defp decode_tag(1, value, %{decode_epoch_time: false}), do: %CBOR.Tag{tag: 1, value: value}

  defp decode_tag(1, value, _ctx) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, dt} -> dt
      {:error, _} -> %CBOR.Tag{tag: 1, value: value}
    end
  end

  # Sub-microsecond precision is lost: `DateTime` stores microseconds, and
  # for epochs of "modern" magnitude (≥10^9 s) the float's own ULP is already
  # ≥250 ns, so finer granularity would not survive the round-trip anyway.
  defp decode_tag(1, value, _ctx) when is_float(value) do
    case DateTime.from_unix(trunc(value * 1_000_000), :microsecond) do
      {:ok, dt} -> dt
      {:error, _} -> %CBOR.Tag{tag: 1, value: value}
    end
  rescue
    # `value * 1_000_000` overflows for finite floats near the double max,
    # raising either ArithmeticError (on the multiply) or ArgumentError
    # (on `trunc(±∞)`). Fall back to the wrapped tag rather than crashing.
    _ in [ArithmeticError, ArgumentError] -> %CBOR.Tag{tag: 1, value: value}
  end

  # Tag 2 (positive bignum) and tag 3 (negative bignum, value = -n - 1)
  # differ only in the integer transformation. RFC 8949 §3.4.3 requires
  # byte-string content; lenient mode wraps non-byte-string content via
  # `%CBOR.Tag{}` (consistent with how tags 0/32/100/1004 handle invalid
  # content) rather than coercing text-string bytes to an integer (a
  # type-confusion path). The library's encoder always wraps bignum
  # payload as `:bytes`, so only hand-crafted bytes or non-conforming
  # peer input exercises the wrap path.
  defp decode_tag(2, value, ctx), do: decode_bignum(2, value, ctx, & &1)
  defp decode_tag(3, value, ctx), do: decode_bignum(3, value, ctx, &(-&1 - 1))

  defp decode_tag(32, value, %{strict: true}) when is_binary(value) do
    case URI.new(value) do
      {:ok, uri} -> uri
      {:error, _} -> throw({:cbor_invalid_tag, 32, :not_uri_reference})
    end
  end

  defp decode_tag(32, _value, %{strict: true}) do
    throw({:cbor_invalid_tag, 32, :not_uri_reference})
  end

  defp decode_tag(32, value, _ctx) when is_binary(value) do
    case URI.new(value) do
      {:ok, uri} -> uri
      {:error, _} -> %CBOR.Tag{tag: 32, value: value}
    end
  end

  # Tag 100 — days since 1970-01-01 (RFC 8943). Uses Howard Hinnant's
  # closed-form `civil_from_days` (https://howardhinnant.github.io/date_algorithms.html)
  # in O(1). `Date.add/2` and `Date.shift/2` both scale linearly in the
  # offset magnitude (`Calendar.ISO.days_to_year/1` iterates year-by-year),
  # which surfaced as a DoS in fuzz testing for uint64-sized offsets.
  # The closed-form decomposition lets the parser handle any 64-bit
  # offset in microseconds.
  defp decode_tag(100, days, _ctx) when is_integer(days) do
    date_from_days(days)
  rescue
    _ in [ArgumentError] -> %CBOR.Tag{tag: 100, value: days}
  end

  # Tag 258 — mathematical finite set (community spec, cbor-sets-spec).
  defp decode_tag(258, value, _ctx) when is_list(value), do: MapSet.new(value)

  # Tag 1004 — RFC 3339 full-date text string (RFC 8943).
  defp decode_tag(1004, value, _ctx) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> %CBOR.Tag{tag: 1004, value: value}
    end
  end

  # Tag 55799 — self-described CBOR (RFC 8949 §3.4.6); strip the marker.
  defp decode_tag(55_799, value, _ctx), do: value

  defp decode_tag(tag, value, ctx) do
    case Map.get(ctx.tag_decoders, tag) do
      nil ->
        maybe_validate_tag_24_strict!(tag, value, ctx)
        %CBOR.Tag{tag: tag, value: value}

      decoder ->
        apply_tag_decoder(decoder, tag, value, ctx)
    end
  end

  # RFC 8949 §3.4.5.1: a tag 24 byte string MUST contain exactly one
  # well-formed CBOR data item. Strict-mode callers without
  # `CBOR.TagDecoders.EncodedCBOR` registered would otherwise miss this
  # check (the wrapped fallback would silently accept malformed inner
  # bytes). Reuses `EncodedCBOR.decode/2` so the validation logic lives
  # in one place; the decoded value is discarded — strict mode validates
  # without changing the success-path shape, which stays
  # `%CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes, ...}}` unless the
  # caller also opts into unwrapping by registering `EncodedCBOR`.
  defp maybe_validate_tag_24_strict!(24, value, %{strict: true} = ctx) do
    case EncodedCBOR.decode(value, ctx_to_opts(ctx)) do
      {:ok, _decoded} -> :ok
      {:error, reason} -> throw({:cbor_invalid_tag, 24, reason})
      :error -> throw({:cbor_invalid_tag, 24, :non_byte_string_content})
    end
  end

  defp maybe_validate_tag_24_strict!(_tag, _value, _ctx), do: :ok

  defp decode_bignum(_tag, %CBOR.Tag{tag: :bytes, value: bytes}, _ctx, finalize) when is_binary(bytes) do
    finalize.(bignum_from_bytes(bytes))
  end

  defp decode_bignum(tag, _value, %{strict: true}, _finalize) do
    throw({:cbor_invalid_tag, tag, :non_byte_string_content})
  end

  defp decode_bignum(tag, value, _ctx, _finalize) do
    %CBOR.Tag{tag: tag, value: value}
  end

  # User-supplied `decode/1`/`decode/2` implementations run inside a sandbox:
  # any raise, throw, exit, or non-conforming return value is re-emitted as a
  # typed `{:tag_decoder_raised, tag, reason}` error rather than crashing the
  # parser or being silently re-labelled by the public rescue.
  defp apply_tag_decoder(decoder, tag, value, ctx) do
    case safely_call(decoder, tag, value, ctx) do
      {:ok, decoded} -> decoded
      :error -> %CBOR.Tag{tag: tag, value: value}
      {:error, reason} -> throw({:cbor_tag_decoder_failed, tag, reason})
      other -> throw({:cbor_tag_decoder_raised, tag, {:bad_return, other}})
    end
  end

  # Returns the decoder's result on normal completion; throws a typed
  # error if it raised, threw, or exited. Prefers `decode/2` (which receives
  # a snapshot of the outer call's options) when the decoder exports it, so
  # decoders that re-enter `CBOR.decode/2` inherit `:max_depth`, `:strict`,
  # and the rest of the ctx.
  defp safely_call(decoder, tag, value, ctx) do
    if function_exported?(decoder, :decode, 2) do
      decoder.decode(value, ctx_to_opts(ctx))
    else
      decoder.decode(value)
    end
  rescue
    exception -> throw({:cbor_tag_decoder_raised, tag, {:raise, exception}})
  catch
    kind, payload -> throw({:cbor_tag_decoder_raised, tag, {kind, payload}})
  end

  defp ctx_to_opts(ctx) do
    [
      max_depth: max(ctx.max_depth - ctx.depth, 0),
      strict: ctx.strict,
      on_duplicate_key: ctx.on_duplicate_key,
      decode_epoch_time: ctx.decode_epoch_time,
      tag_decoders: Map.values(ctx.tag_decoders)
    ]
  end

  defp bignum_from_bytes(bytes) do
    size = byte_size(bytes)
    <<res::unsigned-integer-size(^size)-unit(8)>> = bytes
    res
  end

  # Convert days-since-1970-01-01 to a Date in O(1). Howard Hinnant's
  # closed-form `civil_from_days` algorithm. The +719_468 offset rebases
  # onto Hinnant's 0000-03-01-anchored "era" arithmetic, which aligns
  # leap-day handling at the end of each year and lets the math decompose
  # cleanly via div/rem by 400/100/4-year cycles.
  # Reference: https://howardhinnant.github.io/date_algorithms.html
  #
  # Sunset: drop this routine and use `Date.add(~D[1970-01-01], days)` once
  # the `:elixir` requirement in `mix.exs` is bumped to >= 1.20. Earlier
  # versions iterate year-by-year inside `Calendar.ISO.days_to_year/1`,
  # which is a DoS vector for uint64-sized offsets. Tag 100 fuzz testing
  # surfaced this; the closed-form returns in ~9 µs for any 64-bit input.
  defp date_from_days(days) do
    z = days + 719_468
    era = if z >= 0, do: div(z, 146_097), else: div(z - 146_096, 146_097)
    doe = z - era * 146_097
    yoe = div(doe - div(doe, 1460) + div(doe, 36_524) - div(doe, 146_096), 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))
    mp = div(5 * doy + 2, 153)
    d = doy - div(153 * mp + 2, 5) + 1
    m = mp + if(mp < 10, do: 3, else: -9)
    y = if m <= 2, do: y + 1, else: y
    Date.new!(y, m, d)
  end

  defp decode_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} ->
        datetime

      {:ok, utc_datetime, offset_seconds} ->
        rebuild_with_offset(utc_datetime, offset_seconds)

      {:error, _reason} ->
        decode_date(value)
    end
  end

  # RFC 8949 §3.4.1 / RFC 3339 §5.6: tag 0 wire format includes the
  # time-offset, which carries presentation context. Constructing the
  # DateTime manually with synthetic zone fields preserves the offset
  # without requiring a tz database — a tz database is only needed for
  # inter-zone conversions (DST, historical changes), not for representing
  # a fixed-offset DateTime.
  defp rebuild_with_offset(utc_datetime, offset_seconds) do
    local_datetime = DateTime.add(utc_datetime, offset_seconds, :second)
    zone = format_offset_zone(offset_seconds)

    %{
      local_datetime
      | utc_offset: offset_seconds,
        std_offset: 0,
        time_zone: zone,
        zone_abbr: zone
    }
  end

  defp format_offset_zone(seconds) do
    sign = if seconds >= 0, do: "+", else: "-"
    abs_seconds = abs(seconds)
    hours = div(abs_seconds, 3600)
    minutes = div(rem(abs_seconds, 3600), 60)

    "#{sign}#{pad2(hours)}:#{pad2(minutes)}"
  end

  defp pad2(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp decode_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> decode_time(value)
    end
  end

  defp decode_time(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> time
      {:error, _reason} -> %CBOR.Tag{tag: 0, value: value}
    end
  end
end
