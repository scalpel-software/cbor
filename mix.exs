defmodule Cbor.MixProject do
  use Mix.Project

  def project do
    [
      app: :cbor,
      version: "1.0.0",
      elixir: "~> 1.0",
      start_permanent: Mix.env() == :prod,
      description: "Implementation of RFC 7049 (Concise Binary Object Representation)",
      package: [
        maintainers: ["tomciopp"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/scalpel-software/cbor"}
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
