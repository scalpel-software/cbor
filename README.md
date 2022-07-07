# CBOR

[![Module Version](https://img.shields.io/hexpm/v/cbor.svg)](https://hex.pm/packages/cbor)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/cbor/)
[![Total Download](https://img.shields.io/hexpm/dt/cbor.svg)](https://hex.pm/packages/cbor)
[![License](https://img.shields.io/hexpm/l/cbor.svg)](https://github.com/scalpel-software/cbor/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/scalpel-software/cbor.svg)](https://github.com/scalpel-software/cbor/commits/master)

Implementation of RFC 7049 [CBOR](http://cbor.io) (Concise Binary
Object Representation) for Elixir.

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

## Installation

```elixir
def deps do
  [
    {:cbor, "~> 1.0.0"}
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

`CBOR.Tag` is also useful if you want to extend `CBOR` for internal applications

## Custom Encoding

If you want to encode something that is not supported out of the box you can implement the `CBOR.Encoder` protocol for the module. You only have to implement a single `CBOR.Encoder.encode_into/2` function. An example for encoding a Money struct is given below.

```elixir
defimpl CBOR.Encoder, for: Money do
  def encode_into(money, acc) do
    money |> Money.to_string() |> CBOR.Encoder.encode_into(acc)
  end
end
```

## Custom Decoding

If you want to decode something that is not supported out of the box you can add a custom tag decoder function with the `tag_decoder` option into `CBOR.decode/1`. The function should take in a `CBOR.Tag` struct and convert the value based on the tag. An example for decoding Tuples and Atoms with a custom tags is shown below.

```elixir
# Tag 50 represents Tuples, tag 51 represents Atoms. Tag numbers chosen arbitrarily.
defmodule TupleDecoder do
  def tag_decoder(tag_struct) do
    case tag_struct.tag do
      50 ->
        List.to_tuple(tag_struct.value)
      51 ->
        String.to_atom(tag_struct.value)
      _ ->
        tag_struct
    end
  end
end

iex(1)> bin_tuple = CBOR.encode(%CBOR.Tag{tag: 50, value: {%CBOR.Tag{tag: 51, value: "atom"}, %CBOR.Tag{tag: 50, value: {"nested_tuple", 1, 2}}}})

iex(2)> CBOR.decode(bin_tuple, tag_decoder: TupleDecoder.tag_decoder)
{:ok, {:atom, {"nested_tuple", 1, 2}}, ""}

iex(3)> CBOR.decode(bin_tuple)
{:ok,
 %CBOR.Tag{
   tag: 50,
   value: [
     %CBOR.Tag{tag: 51, value: "atom"},
     %CBOR.Tag{tag: 50, value: ["nested_tuple", 1, 2]}
   ]
 }, ""}
```

### Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/cbor](https://hexdocs.pm/cbor).


## Copyright and License

Copyright (c) 2019 Thomas Cioppettini

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
