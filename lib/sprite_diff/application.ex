defmodule SpriteDiff.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # This is a CLI tool - run CLI and exit
    # Skip CLI mode only when running in IEx or tests
    unless iex_running?() or mix_env_test?() do
      args = System.argv()
      SpriteDiff.CLI.main(args)
      System.halt(0)
    end

    # For IEx/test mode, start minimal supervisor
    children = []
    opts = [strategy: :one_for_one, name: SpriteDiff.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

  defp mix_env_test? do
    function_exported?(Mix, :env, 0) and Mix.env() == :test
  end
end
