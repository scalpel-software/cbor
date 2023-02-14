defmodule Cbor.MixProject do
  use Mix.Project

  @source_url "https://github.com/scalpel-software/cbor"
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: "Implementation of RFC 7049 (Concise Binary Object Representation)",
      maintainers: ["tomciopp"],
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
