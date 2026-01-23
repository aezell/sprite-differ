defmodule SpriteDiff.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Start supervisor first (required by OTP)
    children = []
    opts = [strategy: :one_for_one, name: SpriteDiff.Supervisor]
    {:ok, _pid} = Supervisor.start_link(children, opts)

    # Always run CLI - this is a CLI tool
    args = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
    SpriteDiff.CLI.main(args)
    System.halt(0)
  end
end
