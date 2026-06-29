defmodule Lightpanda.MixProject do
  use Mix.Project

  @version "0.3.4-rc.0"
  @source_url "https://github.com/u2i/lightpanda"

  def project do
    [
      app: :lightpanda,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Mix tasks for installing and invoking the Lightpanda headless browser (u2i fork build with cookie-on-WS-upgrade fix)",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Lightpanda.Application, []}
    ]
  end

  defp deps do
    [
      {:castore, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["U2i"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Lightpanda" => "https://github.com/lightpanda-io/browser"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "Lightpanda",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
