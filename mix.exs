defmodule Cbor.MixProject do
  use Mix.Project

  @source_url "https://github.com/vLEIDA/cbor"
  @version "1.0.1"

  def project do
    [
      app: :cbor,
      version: @version,
      elixir: "~> 1.0",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ord_map, "~> 0.1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "cbor_ordmap",
      description: "Implementation of RFC 7049 (Concise Binary Object Representation) with support for serializing/deserializing to an ordered map representation.",
      maintainers: ["daidoji", "dc7"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      extras: [
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "#v{@version}",
      formatters: ["html"]
    ]
  end
end
