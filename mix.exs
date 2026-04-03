defmodule Lightpanda.MixProject do
  use Mix.Project

  @version "0.2.8"
  @source_url "https://github.com/u2i/lightpanda"

  def project do
    [
      app: :lightpanda,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Mix tasks for installing and invoking the Lightpanda headless browser",
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
      {:ex_doc, ">= 0.0.0", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["U2i"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Lightpanda" => "https://github.com/lightpanda-io/browser"
      }
    ]
  end

  defp docs do
    [
      main: "Lightpanda",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
