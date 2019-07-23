defmodule CBOR.EncoderTest do
  use ExUnit.Case, async: true

  defp reconstruct(value) do
    value |> CBOR.encode() |> CBOR.decode()
  end

  test "given the value of true" do
    assert reconstruct(true) == {:ok, true}
  end

  test "given the value of false" do
    assert reconstruct(false) == {:ok, false}
  end

  test "given the value of nil" do
    assert reconstruct(nil) == {:ok, nil}
  end

  test "given the value of undefined" do
    assert reconstruct(:__undefined__) == {:ok, :__undefined__}
  end

  test "given an empty list" do
    assert reconstruct([]) == {:ok, []}
  end

  test "given an integer" do
    assert reconstruct(1) == {:ok, 1}
  end

  test "given an bignum" do
    assert reconstruct(51090942171709440000) == {:ok, 51090942171709440000}
  end

  test "given a list with several items" do
    assert reconstruct([1,2,3,4,5,6,7,8]) == {:ok, [1,2,3,4,5,6,7,8]}
  end

  test "given a complex nested list" do
    assert reconstruct([1, [2, 3], [4, 5]]) == {:ok, [1, [2, 3], [4, 5]]}
  end

  test "given a tuple, it converts it to a list" do
    assert reconstruct({}) == {:ok, []}
  end

  test "given a tuple with several items" do
    assert reconstruct({1,2,3,4,5,6,7,8}) == {:ok, [1,2,3,4,5,6,7,8]}
  end

  test "given a complex nested tuple" do
    assert reconstruct({1, {2, 3}, {4, 5}}) == {:ok, [1, [2, 3], [4, 5]]}
  end

  test "given a URI" do
    uri = %URI{
      authority: "www.example.com",
      fragment: nil,
      host: "www.example.com",
      path: nil,
      port: 80,
      query: nil,
      scheme: "http",
      userinfo: nil
    }

    assert reconstruct(uri) == {:ok, uri}
  end

  test "given 0.0" do
    assert reconstruct(0.0) == {:ok, 0.0}
  end

  test "given 0.1" do
    assert reconstruct(0.1) == {:ok, 0.1}
  end

  test "given 1.0" do
    assert reconstruct(0.0) == {:ok, 0.0}
  end

  test "given 1.1" do
    assert reconstruct(0.1) == {:ok, 0.1}
  end

  test "given a bignum" do
    assert reconstruct(2432902008176640000) == {:ok, 2432902008176640000}
  end

  test "given a datetime" do
    assert reconstruct(~U[2013-03-21 20:04:00Z]) == {:ok, ~U[2013-03-21 20:04:00Z]}
  end

  test "given a naive datetime" do
    assert reconstruct(~N[2019-07-22 17:17:40.564490]) == {:ok, ~U[2019-07-22 17:17:40.564490Z]}
  end

  test "given a range" do
    assert reconstruct(1..10) == {:ok, [1,2,3,4,5,6,7,8,9,10]}
  end

  test "complex maps" do
    assert reconstruct(%{"a" => 1, "b" => [2, 3]}) == {:ok, %{"a" => 1, "b" => [2, 3]}}
  end

  test "given a date" do
    assert reconstruct(~D[2000-01-01]) == {:ok, ~D[2000-01-01]}
  end

  test "given a time" do
    assert reconstruct(~T[23:00:07.001]) == {:ok, ~T[23:00:07.001]}
  end
end
