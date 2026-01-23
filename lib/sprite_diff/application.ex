defmodule SpriteDiff.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # This is a CLI tool - run CLI and exit
    # Skip CLI mode only when running in IEx
    unless Code.ensure_loaded?(IEx) and function_exported?(IEx, :started?, 0) and IEx.started?() do
      args = get_args()
      SpriteDiff.CLI.main(args)
      System.halt(0)
    end

    # For IEx mode, start minimal supervisor
    children = []
    opts = [strategy: :one_for_one, name: SpriteDiff.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_args do
    # In Burrito/releases, use :init.get_plain_arguments()
    # which returns charlist args - convert to strings
    :init.get_plain_arguments()
    |> Enum.map(&List.to_string/1)
  end
end
