defmodule SpriteDiff.CLI.Remote do
  @moduledoc """
  CLI handlers for remote commands: checkpoints, manifest, diff, file.
  """

  alias SpriteDiff.{API, Manifest, Diff, Formatter}

  def run(opts, ["checkpoints", sprite_name]) do
    case API.list_checkpoints(sprite_name) do
      {:ok, checkpoints} ->
        if opts[:json] do
          IO.puts(Jason.encode!(checkpoints, pretty: true))
        else
          Formatter.print_checkpoints(checkpoints, sprite_name)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(opts, ["manifest", sprite_name, checkpoint_id]) do
    IO.puts("Generating manifest for #{sprite_name}@#{checkpoint_id}...")

    case Manifest.generate(sprite_name, checkpoint_id) do
      {:ok, manifest} ->
        output = if opts[:json], do: Jason.encode!(manifest, pretty: true), else: Formatter.format_manifest(manifest)

        case opts[:output] do
          nil -> IO.puts(output)
          path -> File.write!(path, output)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(opts, ["diff", sprite_name, checkpoint_a, checkpoint_b]) do
    IO.puts("Comparing #{checkpoint_a} → #{checkpoint_b}...")

    case Diff.compare(sprite_name, checkpoint_a, checkpoint_b) do
      {:ok, diff_result} ->
        if opts[:json] do
          IO.puts(Jason.encode!(diff_result, pretty: true))
        else
          if opts[:summary] do
            Formatter.print_diff_summary(diff_result)
          else
            Formatter.print_diff(diff_result)
          end
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(_opts, ["file", sprite_name, checkpoint_a, checkpoint_b, file_path]) do
    IO.puts("Diffing #{file_path}...")

    case Diff.file_diff(sprite_name, checkpoint_a, checkpoint_b, file_path) do
      {:ok, content_diff} ->
        Formatter.print_file_diff(file_path, content_diff)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end
end
