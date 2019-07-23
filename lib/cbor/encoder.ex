defprotocol CBOR.Encoder do
  @doc "Converts an Elixir data type to its representation in CBOR"
  def encode_into(element, acc)
end

defimpl CBOR.Encoder, for: Atom do
  def encode_into(false, acc), do: <<acc::binary, 0xf4>>
  def encode_into(true, acc), do: <<acc::binary, 0xf5>>
  def encode_into(nil, acc), do: <<acc::binary, 0xf6>>
  def encode_into(:__undefined__, acc), do: <<acc::binary, 0xf7>>
  def encode_into(v, acc), do: CBOR.Utils.encode_string(3, Atom.to_string(v), acc)
end

defimpl CBOR.Encoder, for: BitString do
  def encode_into(s, acc), do: CBOR.Utils.encode_string(3, s, acc)
end

defimpl CBOR.Encoder, for: CBOR.Tag do
  def encode_into(%CBOR.Tag{tag: :bytes, value: s}, acc) do
    CBOR.Utils.encode_string(2, s, acc)
  end

  def encode_into(%CBOR.Tag{tag: :float, value: :inf}, acc) do
    <<acc::binary, 0xf9, 0x7c, 0>>
  end

  def encode_into(%CBOR.Tag{tag: :float, value: :"-inf"}, acc) do
    <<acc::binary, 0xf9, 0xfc, 0>>
  end

  def encode_into(%CBOR.Tag{tag: :float, value: :nan}, acc) do
    <<acc::binary, 0xf9, 0x7e, 0>>
  end

  def encode_into(%CBOR.Tag{tag: :simple, value: val}, acc) when val < 0x100 do
    CBOR.Utils.encode_head(7, val, acc)
  end

  def encode_into(%CBOR.Tag{tag: tag, value: val}, acc) do
    CBOR.Encoder.encode_into(val, CBOR.Utils.encode_head(6, tag, acc))
  end
end

defimpl CBOR.Encoder, for: Date do
  def encode_into(time, acc) do
    CBOR.Encoder.encode_into(
      Date.to_iso8601(time),
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

defimpl CBOR.Encoder, for: DateTime do
  def encode_into(datetime, acc) do
    CBOR.Encoder.encode_into(
      DateTime.to_iso8601(datetime),
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

defimpl CBOR.Encoder, for: Float do
  def encode_into(x, acc), do: <<acc::binary, 0xfb, x::float>>
end

defimpl CBOR.Encoder, for: Integer do
  def encode_into(i, acc) when i >= 0 and i < 0x10000000000000000 do
    CBOR.Utils.encode_head(0, i, acc)
  end

  def encode_into(i, acc) when i < 0 and i >= -0x10000000000000000 do
    CBOR.Utils.encode_head(1, -i - 1, acc)
  end

  def encode_into(i, acc) when i >= 0, do: encode_as_bignum(i, 2, acc)
  def encode_into(i, acc) when i < 0, do: encode_as_bignum(-i - 1, 3, acc)

  defp encode_as_bignum(i, tag, acc) do
    CBOR.Utils.encode_string(
      2,
      :binary.encode_unsigned(i),
      CBOR.Utils.encode_head(6, tag, acc)
    )
  end
end

defimpl CBOR.Encoder, for: List do
  def encode_into([], acc), do: <<acc::binary, 0x80>>

  def encode_into(list, acc) when length(list) < 0x10000000000000000 do
    Enum.reduce(list, CBOR.Utils.encode_head(4, length(list), acc), fn(v, acc) ->
      CBOR.Encoder.encode_into(v, acc)
    end)
  end

  def encode_into(list, acc) do
    Enum.reduce(list, <<acc::binary, 0x9f>>, fn(v, acc) ->
      CBOR.Encoder.encode_into(v, acc)
    end) <> <<0xff>>
  end
end

defimpl CBOR.Encoder, for: Map do
  def encode_into(map, acc) when map_size(map) == 0, do: <<acc::binary, 0xa0>>

  def encode_into(map, acc) when map_size(map) < 0x10000000000000000 do
    Enum.reduce(map, CBOR.Utils.encode_head(5, map_size(map), acc), fn({k, v}, subacc) ->
      CBOR.Encoder.encode_into(v, CBOR.Encoder.encode_into(k, subacc))
    end)
  end

  def encode_into(map, acc) do
    Enum.reduce(map, <<acc::binary, 0xbf>>, fn({k, v}, subacc) ->
      CBOR.Encoder.encode_into(v, CBOR.Encoder.encode_into(k, subacc))
    end) <> <<0xff>>
  end
end

# We convert MapSets into lists since there is no 'set' representation
defimpl CBOR.Encoder, for: MapSet do
  def encode_into(map_set, acc) do
    map_set |> MapSet.to_list() |> CBOR.Encoder.encode_into(acc)
  end
end

# We treat all NaiveDateTimes as UTC, if you need to include TimeZone
# information you should convert your data to a regular DateTime
defimpl CBOR.Encoder, for: NaiveDateTime do
  def encode_into(naive_datetime, acc) do
    CBOR.Encoder.encode_into(
      NaiveDateTime.to_iso8601(naive_datetime) <> "Z",
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

# We convert Ranges into lists since there is no 'range' representation
defimpl CBOR.Encoder, for: Range do
  def encode_into(range, acc) do
    range |> Enum.into([]) |> CBOR.Encoder.encode_into(acc)
  end
end

defimpl CBOR.Encoder, for: Time do
  def encode_into(time, acc) do
    CBOR.Encoder.encode_into(
      Time.to_iso8601(time),
      CBOR.Utils.encode_head(6, 0, acc)
    )
  end
end

# We convert all Tuples to Lists since CBOR has no concept of Tuples,
# and they are basically the same thing anyway. This also fixes the problem
# of having to deal with keyword lists so we don't lose any information.
defimpl CBOR.Encoder, for: Tuple do
  def encode_into(tuple, acc) do
    tuple |> Tuple.to_list() |> CBOR.Encoder.encode_into(acc)
  end
end

defimpl CBOR.Encoder, for: URI do
  def encode_into(uri, acc) do
    CBOR.Encoder.encode_into(
      URI.to_string(uri),
      CBOR.Utils.encode_head(6, 32, acc)
    )
  end
end
