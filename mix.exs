defmodule SpriteDiff.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :sprite_diff,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      releases: releases()
    ]
  end

  def escript do
    [main_module: SpriteDiff.CLI, name: :"sprite-differ"]
  end

  def releases do
    [
      sprite_differ: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_aarch64: [os: :linux, cpu: :aarch64],
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            macos_aarch64: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {SpriteDiff.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:makeup, "~> 1.1"},
      {:makeup_elixir, "~> 0.16"},
      {:makeup_js, "~> 0.1"},
      {:burrito, "~> 1.0"}
    ]
  end
end
