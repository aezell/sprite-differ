defmodule SpriteDiff.CLI.Agent do
  @moduledoc """
  CLI handlers for agent commands: install, status, uninstall, trigger.
  """

  alias SpriteDiff.{Agent, Formatter}

  def run(_opts, ["agent", "install", sprite_name]) do
    IO.puts("Installing sprite-diff agent on #{sprite_name}...")

    case Agent.install(sprite_name) do
      :ok ->
        IO.puts("Agent installed successfully.")
        IO.puts("Manifests will be created automatically at checkpoints.")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(_opts, ["agent", "status", sprite_name]) do
    case Agent.status(sprite_name) do
      {:ok, status} ->
        Formatter.print_agent_status(status)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(_opts, ["agent", "uninstall", sprite_name]) do
    IO.puts("Uninstalling sprite-diff agent from #{sprite_name}...")

    case Agent.uninstall(sprite_name) do
      :ok ->
        IO.puts("Agent uninstalled successfully.")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(_opts, ["agent", "trigger", sprite_name]) do
    IO.puts("Triggering manifest creation on #{sprite_name}...")

    case Agent.trigger_manifest(sprite_name) do
      {:ok, manifest_path} ->
        IO.puts("Manifest created: #{manifest_path}")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end
end
