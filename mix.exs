defmodule SpriteDiff.MixProject do
  use Mix.Project

  def project do
    [
      app: :sprite_diff,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  def escript do
    [main_module: SpriteDiff.CLI, name: :"sprite-differ"]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SpriteDiff.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:makeup, "~> 1.1"},
      {:makeup_elixir, "~> 0.16"},
      {:makeup_js, "~> 0.1"}
    ]
  end
end
