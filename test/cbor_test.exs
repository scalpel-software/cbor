defmodule CBORTest do
  use ExUnit.Case

  doctest CBOR

  describe "format_error/1" do
    # One assertion per `decode_error()` variant. Strings are pinned
    # so messages stay stable for downstream pattern-matchers / log
    # parsers; a deliberate copy change must update the test.

    test ":cannot_decode_non_binary_values" do
      assert CBOR.format_error(:cannot_decode_non_binary_values) ==
               "CBOR.decode/2 expects a binary input"
    end

    test "{:duplicate_key, key}" do
      assert CBOR.format_error({:duplicate_key, "a"}) ==
               "CBOR map contained a duplicate key (option `on_duplicate_key: :error`): \"a\""
    end

    for {reason, fragment} <- [
          {:malformed_header, "malformed initial byte"},
          {:truncated, "ended mid-data-item"},
          {:malformed, "not well-formed"},
          {:indefinite_length_not_allowed, "App. F subkind 5"},
          {:stray_break_code, "stray break code"},
          {:nested_indefinite_string, "§3.2.3"},
          {:reserved_simple_value_form, "§3.3"}
        ] do
      test "{:not_well_formed, #{inspect(reason)}}" do
        msg = CBOR.format_error({:not_well_formed, unquote(reason)})
        assert msg =~ unquote(fragment)
        assert String.starts_with?(msg, "CBOR input ")
      end
    end

    test "{:invalid_tag, _, :non_byte_string_content}" do
      assert CBOR.format_error({:invalid_tag, 2, :non_byte_string_content}) ==
               "CBOR tag 2 content was not a byte string (RFC 8949 §3.4.3)"
    end

    test "{:invalid_tag, _, :not_uri_reference}" do
      assert CBOR.format_error({:invalid_tag, 32, :not_uri_reference}) ==
               "CBOR tag 32 content was not a valid URI reference (RFC 8949 §3.4.5.3)"
    end

    test "{:tag_decoder_raised, _, {:raise, exception}}" do
      msg = CBOR.format_error({:tag_decoder_raised, 99, {:raise, %RuntimeError{message: "boom"}}})
      assert msg =~ "tag 99"
      assert msg =~ "RuntimeError"
      assert msg =~ "boom"
    end

    for kind <- [:throw, :exit, :bad_return] do
      test "{:tag_decoder_raised, _, {#{inspect(kind)}, _}}" do
        msg = CBOR.format_error({:tag_decoder_raised, 99, {unquote(kind), :payload}})
        assert msg =~ "tag 99"
        assert msg =~ ":payload"
      end
    end

    test "{:tag_decoder_failed, _, _}" do
      msg = CBOR.format_error({:tag_decoder_failed, 24, :trailing_bytes})
      assert msg =~ "tag 24"
      assert msg =~ ":trailing_bytes"
    end

    test "{:max_depth_exceeded, limit}" do
      assert CBOR.format_error({:max_depth_exceeded, 256}) ==
               "CBOR nesting exceeded the configured :max_depth of 256"
    end

    test "defensive fallback for unknown shapes" do
      # Forward-compat: unknown error reasons still produce a non-empty
      # string instead of a FunctionClauseError. Dialyzer enforces the
      # typed case at compile time via the @spec.
      assert CBOR.format_error({:totally_new_reason, 42}) =~ "CBOR error:"
    end

    test "round-trips with actual decode/2 errors (lenient)" do
      # End-to-end fence: a real decode error term flows through
      # format_error/1 without surprises.
      assert {:error, reason} = CBOR.decode(<<>>)
      assert is_binary(CBOR.format_error(reason))
    end

    test "round-trips with actual decode/2 errors (strict)" do
      assert {:error, reason} = CBOR.decode(<<0xC2, 0x05>>, strict: true)
      assert CBOR.format_error(reason) =~ "tag 2"
    end
  end
end
