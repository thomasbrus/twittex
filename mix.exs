defmodule Twittex.Mixfile do
  use Mix.Project

  @version "0.2.3"

  def project do
    [app: :twittex,
     name: "Twittex",
     version: @version,
     elixir: "~> 1.4",
     package: package(),
     description: description(),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     docs: docs(),
     deps: deps()]
  end

  def application do
    [applications: [:logger, :oauth2, :poison, :httpoison, :poolboy, :gen_stage],
     mod: {Twittex, []}]
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Mario Flach"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/almightycouch/twittex"}]
  end

  defp description do
    "Twitter client library for Elixir"
  end

  defp docs do
    [extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/almightycouch/twittex"]
  end

  defp deps do
    [{:poison, "~> 3.1"},
     {:httpoison, "~> 0.11"},
     {:oauth2, "~> 0.9"},
     {:gen_stage, "~> 0.11"},
     {:oauther, "~> 1.1"},
     {:poolboy, "~> 1.5"},
     {:ex_doc, "~> 0.14", only: :dev},
     {:earmark, ">= 0.0.0", only: :dev}]
  end
end
