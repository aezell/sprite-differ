defmodule SpriteDiff.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: SpriteDiff.Supervisor]
    result = Supervisor.start_link(children, opts)

    # When running as a Burrito binary, handle CLI args
    # Burrito sets BURRITO_BIN_PATH when running as a wrapped binary
    if System.get_env("BURRITO_BIN_PATH") do
      args = Burrito.Util.Args.get_arguments()
      SpriteDiff.CLI.main(args)
      System.halt(0)
    end

    result
  end
end
