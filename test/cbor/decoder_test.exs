defmodule CBOR.DecoderTest do
  use ExUnit.Case, async: true

  test "too much data" do
    encoded = <<1, 102, 111, 111>>
    assert CBOR.decode(encoded) == {:ok, 1, "foo"}
  end

  test "too little data" do
    assert_raise(FunctionClauseError, fn ->
      CBOR.Decoder.decode("") == 1
    end)
  end

  # Tag 100 + uint64 max (2^64 - 1). `Date.add/2` would iterate year-by-year
  # through Calendar.ISO and effectively hang. The closed-form
  # `date_from_days/1` returns in microseconds. Surfaced by fuzz testing
  # in `property_test.exs`.
  test "tag 100 with uint64-max days decodes to a Date in O(1) (no DoS)" do
    encoded = <<0xD8, 0x64, 0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

    assert {:ok, %Date{year: 50_505_469_855_535_079, month: 2, day: 21}, ""} =
             CBOR.decode(encoded)
  end

  # Tag 1 + uint64 max. `DateTime.from_unix/1` range-checks before any
  # year-iteration math, so bignum-magnitude integers fail fast with
  # {:error, :invalid_unix_time} and the decoder falls back to a wrapped
  # %CBOR.Tag{}. Verified empirically (~µs).
  # This fence pins the property: a future Elixir regression that turns
  # from_unix/1 into an iterator would blow the 100 ms bound.
  test "tag 1 with uint64-max integer decodes in O(1) (no from_unix DoS)" do
    encoded = <<0xC1, 0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

    {us, result} = :timer.tc(fn -> CBOR.decode(encoded) end)

    assert {:ok, %CBOR.Tag{tag: 1, value: 18_446_744_073_709_551_615}, ""} = result
    assert us < 100_000, "tag 1 decode took #{us} µs (>100 ms); from_unix/1 may have regressed"
  end

  test "a non-binary value" do
    assert CBOR.decode([]) == {:error, :cannot_decode_non_binary_values}
  end

  test "RFC 7049/8949 Appendix A Example 1" do
    encoded = <<0>>
    assert CBOR.decode(encoded) == {:ok, 0, ""}
  end

  test "RFC 7049/8949 Appendix A Example 2" do
    encoded = <<1>>
    assert CBOR.decode(encoded) == {:ok, 1, ""}
  end

  test "RFC 7049/8949 Appendix A Example 3" do
    encoded = "\n"
    assert CBOR.decode(encoded) == {:ok, 10, ""}
  end

  test "RFC 7049/8949 Appendix A Example 4" do
    encoded = <<23>>
    assert CBOR.decode(encoded) == {:ok, 23, ""}
  end

  test "RFC 7049/8949 Appendix A Example 5" do
    encoded = <<24, 24>>
    assert CBOR.decode(encoded) == {:ok, 24, ""}
  end

  test "RFC 7049/8949 Appendix A Example 6" do
    encoded = <<24, 25>>
    assert CBOR.decode(encoded) == {:ok, 25, ""}
  end

  test "RFC 7049/8949 Appendix A Example 7" do
    encoded = <<24, 100>>
    assert CBOR.decode(encoded) == {:ok, 100, ""}
  end

  test "RFC 7049/8949 Appendix A Example 8" do
    encoded = <<25, 3, 232>>
    assert CBOR.decode(encoded) == {:ok, 1000, ""}
  end

  test "RFC 7049/8949 Appendix A Example 9" do
    encoded = <<26, 0, 15, 66, 64>>
    assert CBOR.decode(encoded) == {:ok, 1_000_000, ""}
  end

  test "RFC 7049/8949 Appendix A Example 10" do
    encoded = <<27, 0, 0, 0, 232, 212, 165, 16, 0>>
    assert CBOR.decode(encoded) == {:ok, 1_000_000_000_000, ""}
  end

  test "RFC 7049/8949 Appendix A Example 11" do
    encoded = <<27, 255, 255, 255, 255, 255, 255, 255, 255>>
    assert CBOR.decode(encoded) == {:ok, 18_446_744_073_709_551_615, ""}
  end

  test "RFC 7049/8949 Appendix A Example 12" do
    encoded = <<194, 73, 1, 0, 0, 0, 0, 0, 0, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, 18_446_744_073_709_551_616, ""}
  end

  test "RFC 7049/8949 Appendix A Example 13" do
    encoded = <<59, 255, 255, 255, 255, 255, 255, 255, 255>>
    assert CBOR.decode(encoded) == {:ok, -18_446_744_073_709_551_616, ""}
  end

  test "RFC 7049/8949 Appendix A Example 14" do
    encoded = <<195, 73, 1, 0, 0, 0, 0, 0, 0, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, -18_446_744_073_709_551_617, ""}
  end

  test "RFC 7049/8949 Appendix A Example 15" do
    encoded = " "
    assert CBOR.decode(encoded) == {:ok, -1, ""}
  end

  test "RFC 7049/8949 Appendix A Example 16" do
    encoded = ")"
    assert CBOR.decode(encoded) == {:ok, -10, ""}
  end

  test "RFC 7049/8949 Appendix A Example 17" do
    encoded = "8c"
    assert CBOR.decode(encoded) == {:ok, -100, ""}
  end

  test "RFC 7049/8949 Appendix A Example 18" do
    encoded = <<57, 3, 231>>
    assert CBOR.decode(encoded) == {:ok, -1000, ""}
  end

  test "RFC 7049/8949 Appendix A Example 19" do
    encoded = <<249, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, 0.0, ""}
  end

  test "RFC 7049/8949 Appendix A Example 20" do
    encoded = <<249, 128, 0>>
    assert CBOR.decode(encoded) == {:ok, 0.0, ""}
  end

  test "RFC 7049/8949 Appendix A Example 21" do
    encoded = <<249, 60, 0>>
    assert CBOR.decode(encoded) == {:ok, 1.0, ""}
  end

  test "RFC 7049/8949 Appendix A Example 22" do
    encoded = <<251, 63, 241, 153, 153, 153, 153, 153, 154>>
    assert CBOR.decode(encoded) == {:ok, 1.1, ""}
  end

  test "RFC 7049/8949 Appendix A Example 23" do
    encoded = <<249, 62, 0>>
    assert CBOR.decode(encoded) == {:ok, 1.5, ""}
  end

  test "RFC 7049/8949 Appendix A Example 24" do
    encoded = <<249, 123, 255>>
    assert CBOR.decode(encoded) == {:ok, 65_504.0, ""}
  end

  test "RFC 7049/8949 Appendix A Example 25" do
    encoded = <<250, 71, 195, 80, 0>>
    assert CBOR.decode(encoded) == {:ok, 1.0e5, ""}
  end

  test "RFC 7049/8949 Appendix A Example 26" do
    encoded = <<250, 127, 127, 255, 255>>
    assert CBOR.decode(encoded) == {:ok, 3.402_823_466_385_288_6e38, ""}
  end

  test "RFC 7049/8949 Appendix A Example 27" do
    encoded = <<251, 126, 55, 228, 60, 136, 0, 117, 156>>
    assert CBOR.decode(encoded) == {:ok, 1.0e300, ""}
  end

  test "RFC 7049/8949 Appendix A Example 28" do
    encoded = <<249, 0, 1>>
    assert CBOR.decode(encoded) == {:ok, 5.960464477539063e-8, ""}
  end

  test "RFC 7049/8949 Appendix A Example 29" do
    encoded = <<249, 4, 0>>
    assert CBOR.decode(encoded) == {:ok, 6.103515625e-5, ""}
  end

  test "RFC 7049/8949 Appendix A Example 30" do
    encoded = <<249, 196, 0>>
    assert CBOR.decode(encoded) == {:ok, -4.0, ""}
  end

  test "RFC 7049/8949 Appendix A Example 31" do
    encoded = <<251, 192, 16, 102, 102, 102, 102, 102, 102>>
    assert CBOR.decode(encoded) == {:ok, -4.1, ""}
  end

  test "RFC 7049/8949 Appendix A Example 32" do
    encoded = <<249, 124, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :inf}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 33" do
    encoded = <<249, 126, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :nan}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 34" do
    encoded = <<249, 252, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :"-inf"}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 35" do
    encoded = <<250, 127, 128, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :inf}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 36" do
    encoded = <<250, 127, 192, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :nan}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 37" do
    encoded = <<250, 255, 128, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :"-inf"}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 38" do
    encoded = <<251, 127, 240, 0, 0, 0, 0, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :inf}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 39" do
    encoded = <<251, 127, 248, 0, 0, 0, 0, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :nan}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 40" do
    encoded = <<251, 255, 240, 0, 0, 0, 0, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :float, value: :"-inf"}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 41" do
    encoded = <<244>>
    assert CBOR.decode(encoded) == {:ok, false, ""}
  end

  test "RFC 7049/8949 Appendix A Example 42" do
    encoded = <<245>>
    assert CBOR.decode(encoded) == {:ok, true, ""}
  end

  test "RFC 7049/8949 Appendix A Example 43" do
    encoded = <<246>>
    assert CBOR.decode(encoded) == {:ok, nil, ""}
  end

  test "RFC 7049/8949 Appendix A Example 44" do
    encoded = <<247>>
    assert CBOR.decode(encoded) == {:ok, :__undefined__, ""}
  end

  test "RFC 7049/8949 Appendix A Example 45" do
    encoded = <<240>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :simple, value: 16}, ""}
  end

  # 0xF8 0x18 (= 0xF8, 24) — RFC 7049 listed this as simple(24). RFC 8949
  # §3.3 / Appendix F subkind 2 explicitly reserves v in 24..31 for the
  # two-byte form: there is no canonical encoding for these values and the
  # wire form is not well-formed. Library rejects in both lenient and
  # strict mode.
  test "RFC 7049 Appendix A Example 46 (rejected per RFC 8949 §3.3)" do
    encoded = <<0xF8, 24>>
    assert CBOR.decode(encoded) == {:error, {:not_well_formed, :reserved_simple_value_form}}
  end

  test "RFC 7049/8949 Appendix A Example 47" do
    encoded = <<248, 255>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :simple, value: 255}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 48" do
    encoded = <<192, 116, 50, 48, 49, 51, 45, 48, 51, 45, 50, 49, 84, 50, 48, 58, 48, 52, 58, 48, 48, 90>>
    assert CBOR.decode(encoded) == {:ok, ~U[2013-03-21 20:04:00Z], ""}
  end

  test "RFC 7049/8949 Appendix A Example 49 (tag 1 + integer auto-decodes to DateTime)" do
    encoded = <<193, 26, 81, 75, 103, 176>>
    assert CBOR.decode(encoded) == {:ok, ~U[2013-03-21 20:04:00Z], ""}
  end

  test "RFC 7049/8949 Appendix A Example 50 (tag 1 + float auto-decodes to DateTime)" do
    encoded = <<193, 251, 65, 212, 82, 217, 236, 32, 0, 0>>
    assert CBOR.decode(encoded) == {:ok, ~U[2013-03-21 20:04:00.500000Z], ""}
  end

  test "RFC 7049/8949 Appendix A Example 51" do
    encoded = <<215, 68, 1, 2, 3, 4>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: 23, value: %CBOR.Tag{tag: :bytes, value: <<1, 2, 3, 4>>}}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 52" do
    encoded = <<216, 24, 69, 100, 73, 69, 84, 70>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: 24, value: %CBOR.Tag{tag: :bytes, value: "dIETF"}}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 53" do
    encoded =
      <<216, 32, 118, 104, 116, 116, 112, 58, 47, 47, 119, 119, 119, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111,
        109>>

    assert CBOR.decode(encoded) == {:ok, URI.new!("http://www.example.com"), ""}
  end

  test "RFC 7049/8949 Appendix A Example 54" do
    encoded = "@"
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :bytes, value: ""}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 55" do
    encoded = <<68, 1, 2, 3, 4>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :bytes, value: <<1, 2, 3, 4>>}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 56" do
    assert CBOR.decode("`") == {:ok, "", ""}
  end

  test "RFC 7049/8949 Appendix A Example 57" do
    assert CBOR.decode("aa") == {:ok, "a", ""}
  end

  test "RFC 7049/8949 Appendix A Example 58" do
    assert CBOR.decode("dIETF") == {:ok, "IETF", ""}
  end

  test "RFC 7049/8949 Appendix A Example 59" do
    assert CBOR.decode("b\"\\") == {:ok, "\"\\", ""}
  end

  test "RFC 7049/8949 Appendix A Example 60" do
    assert CBOR.decode("bü") == {:ok, "ü", ""}
  end

  test "RFC 7049/8949 Appendix A Example 61" do
    assert CBOR.decode("c水") == {:ok, "水", ""}
  end

  test "RFC 7049/8949 Appendix A Example 62" do
    assert CBOR.decode("d𐅑") == {:ok, "𐅑", ""}
  end

  test "RFC 7049/8949 Appendix A Example 63" do
    assert CBOR.decode(<<128>>) == {:ok, [], ""}
  end

  test "RFC 7049/8949 Appendix A Example 64" do
    encoded = <<131, 1, 2, 3>>
    assert CBOR.decode(encoded) == {:ok, [1, 2, 3], ""}
  end

  test "RFC 7049/8949 Appendix A Example 65" do
    encoded = <<131, 1, 130, 2, 3, 130, 4, 5>>
    assert CBOR.decode(encoded) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "RFC 7049/8949 Appendix A Example 66" do
    encoded =
      <<152, 25, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 24, 24, 25>>

    assert CBOR.decode(encoded) ==
             {:ok, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25], ""}
  end

  test "RFC 7049/8949 Appendix A Example 67" do
    encoded = <<160>>
    assert CBOR.decode(encoded) == {:ok, %{}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 68" do
    encoded = <<162, 1, 2, 3, 4>>
    assert CBOR.decode(encoded) == {:ok, %{1 => 2, 3 => 4}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 69" do
    encoded = <<162, 97, 97, 1, 97, 98, 130, 2, 3>>
    assert CBOR.decode(encoded) == {:ok, %{"a" => 1, "b" => [2, 3]}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 70" do
    encoded = <<130, 97, 97, 161, 97, 98, 97, 99>>
    assert CBOR.decode(encoded) == {:ok, ["a", %{"b" => "c"}], ""}
  end

  test "RFC 7049/8949 Appendix A Example 71" do
    encoded = <<165, 97, 97, 97, 65, 97, 98, 97, 66, 97, 99, 97, 67, 97, 100, 97, 68, 97, 101, 97, 69>>
    assert CBOR.decode(encoded) == {:ok, %{"a" => "A", "b" => "B", "c" => "C", "d" => "D", "e" => "E"}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 72" do
    encoded = <<95, 66, 1, 2, 67, 3, 4, 5, 255>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: :bytes, value: <<1, 2, 3, 4, 5>>}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 73" do
    encoded = <<127, 101, 115, 116, 114, 101, 97, 100, 109, 105, 110, 103, 255>>
    assert CBOR.decode(encoded) == {:ok, "streaming", ""}
  end

  test "RFC 7049/8949 Appendix A Example 74" do
    encoded = <<159, 255>>
    assert CBOR.decode(encoded) == {:ok, [], ""}
  end

  test "RFC 7049/8949 Appendix A Example 75" do
    encoded = <<159, 1, 130, 2, 3, 159, 4, 5, 255, 255>>
    assert CBOR.decode(encoded) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "RFC 7049/8949 Appendix A Example 76" do
    encoded = <<159, 1, 130, 2, 3, 130, 4, 5, 255>>
    assert CBOR.decode(encoded) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "RFC 7049/8949 Appendix A Example 77" do
    encoded = <<131, 1, 130, 2, 3, 159, 4, 5, 255>>
    assert CBOR.decode(encoded) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "RFC 7049/8949 Appendix A Example 78" do
    encoded = <<131, 1, 159, 2, 3, 255, 130, 4, 5>>
    assert CBOR.decode(encoded) == {:ok, [1, [2, 3], [4, 5]], ""}
  end

  test "RFC 7049/8949 Appendix A Example 79" do
    encoded =
      <<159, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 24, 24, 25, 255>>

    assert CBOR.decode(encoded) ==
             {:ok, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25], ""}
  end

  test "RFC 7049/8949 Appendix A Example 80" do
    encoded = <<191, 97, 97, 1, 97, 98, 159, 2, 3, 255, 255>>
    assert CBOR.decode(encoded) == {:ok, %{"a" => 1, "b" => [2, 3]}, ""}
  end

  test "RFC 7049/8949 Appendix A Example 81" do
    encoded = <<130, 97, 97, 191, 97, 98, 97, 99, 255>>
    assert CBOR.decode(encoded) == {:ok, ["a", %{"b" => "c"}], ""}
  end

  test "RFC 7049/8949 Appendix A Example 82" do
    encoded = <<191, 99, 70, 117, 110, 245, 99, 65, 109, 116, 33, 255>>
    assert CBOR.decode(encoded) == {:ok, %{"Fun" => true, "Amt" => -2}, ""}
  end

  # 0x59 0x6F = byte string of declared length 111, but only 12 bytes follow.
  test "rejects truncated string content" do
    encoded = "You done goofed"
    assert CBOR.decode(encoded) == {:error, {:not_well_formed, :truncated}}
  end

  test "rejects empty input" do
    assert CBOR.decode(<<>>) == {:error, {:not_well_formed, :malformed_header}}
  end

  test "rejects a stray break code at the top level (lenient mode)" do
    assert CBOR.decode(<<0xFF>>) == {:error, {:not_well_formed, :malformed}}
  end

  # 0xc1 = tag 1; 0x1b = uint64 follows; 0xff*8 = 18446744073709551615
  test "tag 1 with out-of-range integer falls back to %CBOR.Tag" do
    encoded = <<0xC1, 0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: 1, value: 18_446_744_073_709_551_615}, ""}
  end

  # 0xd8 0x64 = tag 100 (1-byte argument form); 0x15 = integer 21
  test "tag 100 (days since epoch) decodes to a Date" do
    encoded = <<0xD8, 0x64, 0x15>>
    assert CBOR.decode(encoded) == {:ok, ~D[1970-01-22], ""}
  end

  # 0xd8 0x64 = tag 100; 0x20 = -1
  test "tag 100 with negative days decodes to a pre-1970 Date" do
    encoded = <<0xD8, 0x64, 0x20>>
    assert CBOR.decode(encoded) == {:ok, ~D[1969-12-31], ""}
  end

  # Hinnant `civil_from_days` correctness fences. The algorithm's leap-rule
  # math threads through three nested div/rem cycles (4-year, 100-year,
  # 400-year) and an era-shifted anchor at March 1 of year 0000. Each
  # boundary below exercises one of these:
  #
  #   1900-03-01 — divisible by 100, NOT by 400 → not a leap year
  #   2000-03-01 — divisible by 400 → leap year
  #   2100-03-01 — divisible by 100, NOT by 400 → not a leap year
  #   year -3 boundary — exercises the negative-era branch
  #
  # Days values are computed via `Date.diff/2`, which uses Elixir stdlib's
  # iso-day calculation (not Hinnant). A regression in Hinnant's leap-rule
  # handling at any of these boundaries would produce a different `Date`.
  for {label, date} <- [
        {"1900-03-01 (Gregorian: /100 NOT /400 = non-leap)", ~D[1900-03-01]},
        {"2000-03-01 (Gregorian: /400 = leap)", ~D[2000-03-01]},
        {"2100-03-01 (Gregorian: /100 NOT /400 = non-leap)", ~D[2100-03-01]},
        {"0001-01-01 (early-CE boundary)", ~D[0001-01-01]},
        {"-0003-03-01 (negative-era branch)", Date.new!(-3, 3, 1)}
      ] do
    test "tag 100 fence: #{label}" do
      days = Date.diff(unquote(Macro.escape(date)), ~D[1970-01-01])
      encoded = <<0xD8, 0x64>> <> CBOR.encode(days)
      assert CBOR.decode(encoded) == {:ok, unquote(Macro.escape(date)), ""}
    end
  end

  # 0xd9 0x03 0xec = tag 1004 (2-byte argument form)
  # 0x6a = text string of length 10; "2026-04-29"
  test "tag 1004 (RFC 3339 full-date) decodes to a Date" do
    encoded = <<0xD9, 0x03, 0xEC, 0x6A, "2026-04-29">>
    assert CBOR.decode(encoded) == {:ok, ~D[2026-04-29], ""}
  end

  test "tag 1004 with an unparseable string falls back to %CBOR.Tag" do
    encoded = <<0xD9, 0x03, 0xEC, 0x6A, "not-a-date">>
    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: 1004, value: "not-a-date"}, ""}
  end

  # 0xd9 0x01 0x02 = tag 258; 0x83 = array of length 3; [1, 2, 3]
  test "tag 258 (mathematical finite set) decodes to MapSet" do
    encoded = <<0xD9, 0x01, 0x02, 0x83, 0x01, 0x02, 0x03>>
    assert CBOR.decode(encoded) == {:ok, MapSet.new([1, 2, 3]), ""}
  end

  # 0xd9 0xd9 0xf7 = tag 55799; 0x00 = integer 0
  test "tag 55799 (self-described CBOR) is stripped on decode" do
    encoded = <<0xD9, 0xD9, 0xF7, 0x00>>
    assert CBOR.decode(encoded) == {:ok, 0, ""}
  end

  # Tag 32 wrapping a string with a control char. RFC 3986 forbids control
  # chars in any URI component, so URI.new rejects; the lenient decoder
  # falls back to a generic CBOR.Tag wrapper.
  test "tag 32 with an invalid URI string falls back to %CBOR.Tag in lenient mode" do
    invalid = "bad\x01uri"
    encoded = <<0xD8, 0x20, 0x60 + byte_size(invalid)>> <> invalid

    assert CBOR.decode(encoded) == {:ok, %CBOR.Tag{tag: 32, value: invalid}, ""}
  end

  # 0xd9 0xd9 0xf7 = tag 55799; <<131, 1, 2, 3>> = [1, 2, 3]
  test "tag 55799 wrapping a complex value passes inner value through" do
    encoded = <<0xD9, 0xD9, 0xF7, 131, 1, 2, 3>>
    assert CBOR.decode(encoded) == {:ok, [1, 2, 3], ""}
  end

  # 0xc0 = tag 0; 0x6a = text-string-of-10; "2026-04-29"
  # Pre-v2 emitted dates this way; decoder still accepts for back-compat.
  test "tag 0 with bare ISO 8601 date string still decodes to Date (legacy reader)" do
    encoded = <<0xC0, 0x6A, "2026-04-29">>
    assert CBOR.decode(encoded) == {:ok, ~D[2026-04-29], ""}
  end

  # 0xc0 = tag 0; 0x68 = text-string-of-8; "23:00:07"
  # The encoder still emits this form for Time (no IANA time-of-day tag yet);
  # technically out-of-spec for tag 0, but the fallback chain handles it.
  # Strict mode rejects it, which is correct strict behavior.
  test "tag 0 with bare ISO 8601 time string decodes to Time" do
    encoded = <<0xC0, 0x68, "23:00:07">>
    assert CBOR.decode(encoded) == {:ok, ~T[23:00:07], ""}
  end

  # RFC 8949 §3.4.1 / RFC 3339 §5.6: time-offset is part of the wire
  # format. v1.x normalized non-Z offsets to UTC on decode (lossy
  # round-trip). v2.0 constructs a non-UTC DateTime that preserves the
  # offset so re-encoding produces the same wire bytes.
  describe "tag 0 timezone offset preservation" do
    test "Z form decodes to UTC DateTime and round-trips" do
      bytes = <<0xC0, 0x74, "2024-01-01T00:00:00Z">>
      {:ok, dt, ""} = CBOR.decode(bytes)
      assert dt == ~U[2024-01-01 00:00:00Z]
      assert CBOR.encode(dt) == bytes
    end

    test "+HH:MM offset is preserved on round-trip" do
      bytes = <<0xC0, 0x78, 0x19, "2024-01-01T00:00:00+05:00">>
      {:ok, dt, ""} = CBOR.decode(bytes)
      assert dt.utc_offset == 18_000
      assert dt.time_zone == "+05:00"
      assert dt.year == 2024 and dt.month == 1 and dt.day == 1 and dt.hour == 0
      assert CBOR.encode(dt) == bytes
    end

    test "-HH:MM offset is preserved on round-trip" do
      bytes = <<0xC0, 0x78, 0x19, "2023-12-31T16:00:00-08:00">>
      {:ok, dt, ""} = CBOR.decode(bytes)
      assert dt.utc_offset == -28_800
      assert dt.time_zone == "-08:00"
      assert CBOR.encode(dt) == bytes
    end

    test "boundary offset +14:00 (Kiribati / Line Islands)" do
      bytes = <<0xC0, 0x78, 0x19, "2024-01-01T00:00:00+14:00">>
      {:ok, dt, ""} = CBOR.decode(bytes)
      assert dt.utc_offset == 50_400
      assert CBOR.encode(dt) == bytes
    end

    test "boundary offset -12:00 (Baker / Howland Islands)" do
      bytes = <<0xC0, 0x78, 0x19, "2024-01-01T00:00:00-12:00">>
      {:ok, dt, ""} = CBOR.decode(bytes)
      assert dt.utc_offset == -43_200
      assert CBOR.encode(dt) == bytes
    end

    test "sub-second precision preserved with non-Z offset" do
      bytes = <<0xC0, 0x78, 0x1D, "2024-01-01T00:00:00.500+05:00">>
      {:ok, dt, ""} = CBOR.decode(bytes)
      assert dt.microsecond == {500_000, 3}
      assert CBOR.encode(dt) == bytes
    end

    test "non-Z and Z forms of the same instant compare equal" do
      {:ok, utc_dt, ""} = CBOR.decode(<<0xC0, 0x74, "2023-12-31T19:00:00Z">>)
      {:ok, off_dt, ""} = CBOR.decode(<<0xC0, 0x78, 0x19, "2024-01-01T00:00:00+05:00">>)
      assert DateTime.compare(utc_dt, off_dt) == :eq
      assert DateTime.to_unix(utc_dt) == DateTime.to_unix(off_dt)
    end
  end

  # Half-precision subnormals (exp=0, mant 1..1023). RFC 7049 Example 28
  # already covers mant=1 (smallest positive subnormal); these exercise
  # the rest of the range so a regression in decode_half won't slip past.
  # half: sign=0, exp=0, mant=512 → 512 × 2^-24 = 2^-15
  test "decodes a mid-range half-precision subnormal" do
    assert CBOR.decode(<<0xF9, 0x02, 0x00>>) == {:ok, :math.pow(2, -15), ""}
  end

  # half: sign=0, exp=0, mant=1023 → 1023 × 2^-24
  test "decodes the largest positive half-precision subnormal" do
    assert CBOR.decode(<<0xF9, 0x03, 0xFF>>) == {:ok, 1023 / 16_777_216, ""}
  end

  # half: sign=1, exp=0, mant=512 → -2^-15
  test "decodes a negative half-precision subnormal" do
    assert CBOR.decode(<<0xF9, 0x82, 0x00>>) == {:ok, -:math.pow(2, -15), ""}
  end
end
