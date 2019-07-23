# Cbor

Implementation of RFC 7049 [CBOR](http://cbor.io) (Concise Binary
Object Representation) for Elixir.

This is a fork of [excbor](https://github.com/cabo/excbor) which modernizes
the codebase, and makes decisions on handling data types that the original library had punted on.

## Installation

As of right now, this library is not available on hex, you will have to reference the github link directly. We are currently working on making this the canonical cbor library for elixir.

```elixir
def deps do
  [
    {:cbor, git: "https://github.com/scalpel-software/cbor.git", tag: "0.1"}
  ]
end
```

## Usage

This library follows the standard API for CBOR libraries by exposing two methods
on the CBOR module `encode/1` and `decode/1`.

### Encoding

```elixir
iex(1)> CBOR.encode([1, [2, 3]])
<<130, 1, 130, 2, 3>>
```

### Decoding

```elixir
iex(2)> CBOR.decode(<<130, 1, 130, 2, 3>>)
{:ok, [1, [2, 3]]}
```

## Design Notes

Given that Elixir has more available data types than are supported in CBOR, decisions were made so that encoding complex data structures succeed without throwing errors. My thoughts are collected below so you can understand why encoding and decoding of a value does not necessarily return exactly the same value.

### Atoms

The only atoms that will be directly encoded are `true`, `false` `nil` and `__undefined__`. Every other atom will be converted to a string before being encoded. We surround undefined with double underscores so that you only encode an undefined value when you clearly intend to do so.

### Keyword List, MapSet, Range, Tuple

All of the above data structures are converted to Lists before being encoded. This ensures that there is no data lost when encoding and decoding.

### NaiveDateTime

NaiveDateTime will be treated as if they are UTC.

### Special Values

Elixir and erlang have no concept of infinity, negative infinity and NaN. If you want to encode those values, we have a special struct `CBOR.Tag` which you can use to represent those values.

```elixir
%CBOR.Tag{tag: :float, value: :inf}

%CBOR.Tag{tag: :float, value: :"-inf"}

%CBOR.Tag{tag: :float, value: :nan}
```

CBOR.Tag is also useful if you want to extend CBOR for internal applications

## Custom Encoding

If you want to encode something that is not supported out of the box you can implement the CBOR.Encoder protocol for the module. You only have to implement a single `encode_into/2` function. An example for encoding a Money struct is given below.

```elixir
defimpl CBOR.Encoder, for: Money do
  def encode_into(money, acc) do
    money |> Money.to_string() |> CBOR.Encoder.encode_into(acc)
  end
end
```

### Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/cbor](https://hexdocs.pm/cbor).

