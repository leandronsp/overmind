defmodule Overmind.MixProject do
  use Mix.Project

  def project do
    [
      app: :overmind,
      version: "0.1.0",
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Overmind.CLI],
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Overmind.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      build: ["escript.build"],
      test: ["escript.build", "test"]
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
