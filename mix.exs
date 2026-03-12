defmodule Overmind.MixProject do
  use Mix.Project

  def project do
    [
      app: :overmind,
      version: "0.1.0",
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Overmind.Entrypoint, name: "overmind_daemon"],
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Overmind.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      build: ["escript.build"],
      test: ["escript.build", "test"],
      e2e: ["cmd ./test_e2e.sh"],
      smoke: ["cmd ./test_smoke.sh"]
    ]
  end

  defp deps do
    [
      {:toml, "~> 0.7"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:exqlite, "~> 0.23"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
