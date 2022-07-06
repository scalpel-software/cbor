defmodule CBOR.Decoder do
  def decode(binary) do
    decode(binary, header(binary), &default_decode_tag/2)
  end

  # default_decoder set by caller to decode tags without a set decode value
  def decode(binary, decode_default) do
    decode(binary, header(binary), decode_default)
  end

  def decode(_binary, {mt, :indefinite, rest}, _decode_default) do
    case mt do
      2 -> mark_as_bytes(decode_string_indefinite(rest, 2, []))
      3 -> decode_string_indefinite(rest, 3, [])
      4 -> decode_array_indefinite(rest, [])
      5 -> decode_map_indefinite(rest, %{})
    end
  end

  def decode(bin, {mt, value, rest}, decode_default) do
    case mt do
      0 -> {value, rest}
      1 -> {-value - 1, rest}
      2 -> mark_as_bytes(decode_string(rest, value))
      3 -> decode_string(rest, value)
      4 -> decode_array(value, rest)
      5 -> decode_map(value, rest)
      6 -> decode_other(value, decode(rest), decode_default)
      7 -> decode_float(bin, value, rest)
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
    <<value::binary-size(len), new_rest::binary>> = rest
    {value, new_rest}
  end

  defp decode_string_indefinite(rest, actmt, acc) do
    case header(rest) do
      {7, :indefinite, new_rest} ->
        {Enum.join(Enum.reverse(acc)), new_rest}

      {^actmt, len, mid_rest} ->
        <<value::binary-size(len), new_rest::binary>> = mid_rest
        decode_string_indefinite(new_rest, actmt, [value | acc])
    end
  end

  defp decode_array(0, rest), do: {[], rest}
  defp decode_array(len, rest), do: decode_array(len, [], rest)
  defp decode_array(0, acc, bin), do: {Enum.reverse(acc), bin}
  defp decode_array(len, acc, bin) do
    {value, bin_rest} = decode(bin)
    decode_array(len - 1, [value|acc], bin_rest)
  end

  defp decode_array_indefinite(<<0xff, new_rest::binary>>, acc) do
    {Enum.reverse(acc), new_rest}
  end

  defp decode_array_indefinite(rest, acc) do
    {value, new_rest} = decode(rest)
    decode_array_indefinite(new_rest, [value | acc])
  end

  defp decode_map(0, rest), do: {%{}, rest}
  defp decode_map(len, rest), do: decode_map(len, %{}, rest)
  defp decode_map(0, acc, bin), do: {acc, bin}
  defp decode_map(len, acc, bin) do
    {key, key_rest} = decode(bin)
    {value, bin_rest} = decode(key_rest)

    decode_map(len - 1, Map.put(acc, key, value), bin_rest)
  end

  defp decode_map_indefinite(<<0xff, new_rest::binary>>, acc), do: {acc, new_rest}
  defp decode_map_indefinite(rest, acc) do
    {key, key_rest} = decode(rest)
    {value, new_rest} = decode(key_rest)
    decode_map_indefinite(new_rest, Map.put(acc, key, value))
  end

  defp decode_float(bin, value, rest) do
    case bin do
      <<0xf4, _::binary>> -> {false, rest}
      <<0xf5, _::binary>> -> {true, rest}
      <<0xf6, _::binary>> -> {nil, rest}
      <<0xf7, _::binary>> -> {:__undefined__, rest}

      <<0xf9, sign::size(1), exp::size(5), mant::size(10), _::binary>> ->
        {decode_half(sign, exp, mant), rest}

      <<0xfa, value::float-size(32), _::binary>> ->
         {value, rest}

      <<0xfa, sign::size(1), 255::size(8), mant::size(23), _::binary>> ->
        {decode_non_finite(sign, mant), rest}

      <<0xfb, value::float, _::binary >> ->
        {value, rest}

      <<0xfb, sign::size(1), 2047::size(11), mant::size(52), _::binary>> ->
        {decode_non_finite(sign, mant), rest}

      _ -> {%CBOR.Tag{tag: :simple, value: value}, rest}
    end
  end

  defp decode_other(tag, {value, rest}, decode_default), do: {decode_default.(tag, value), rest}

  def decode_non_finite(0, 0), do: %CBOR.Tag{tag: :float, value: :inf}
  def decode_non_finite(1, 0), do: %CBOR.Tag{tag: :float, value: :"-inf"}
  def decode_non_finite(_, _), do: %CBOR.Tag{tag: :float, value: :nan}

  defp decode_half(sign, 31, mant), do: decode_non_finite(sign, mant)

  # 2**112 -- difference in bias
  defp decode_half(sign, exp, mant) do
    <<value::float-size(32)>> = <<sign::size(1), exp::size(8), mant::size(10), 0::size(13)>>
    value * 5192296858534827628530496329220096.0
  end

  def default_decode_tag(tag, value) do
    decode_tag(tag, value)
  end

  defp decode_tag(0, value), do: decode_datetime(value)

  defp decode_tag(3, value), do: -decode_tag(2, value) - 1

  defp decode_tag(2, value) do
    case value do
      %CBOR.Tag{tag: :bytes, value: bytes} when is_binary(bytes) ->
        size = byte_size(bytes)
        <<res::unsigned-integer-size(size)-unit(8)>> = bytes
        res

      bytes when is_binary(bytes) ->
        size = byte_size(bytes)
        <<res::unsigned-integer-size(size)-unit(8)>> = bytes
        res
    end
  end

  defp decode_tag(32, value), do: URI.parse(value)
  defp decode_tag(tag, value), do: %CBOR.Tag{tag: tag, value: value}

  defp mark_as_bytes({x, rest}), do: {%CBOR.Tag{tag: :bytes, value: x}, rest}

  defp decode_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> decode_date(value)
    end
  end

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
