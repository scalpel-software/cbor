defmodule CborTest do
  use ExUnit.Case
  doctest Cbor

  test "greets the world" do
    assert Cbor.hello() == :world
  end
end
