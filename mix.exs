defmodule Cbor.MixProject do
  use Mix.Project

  @source_url "https://github.com/scalpel-software/cbor"
  @version "2.0.0-rc.1"

  def project do
    [
      app: :cbor,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :extra_return, :missing_return, :underspecs]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: :dev},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.11", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:test], runtime: false}
    ]
  end

  defp package do
    [
      description: "Implementation of RFC 8949 (Concise Binary Object Representation)",
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
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
