defmodule SpriteDiff.CLI do
  @moduledoc """
  Command-line interface for sprite-diff.
  """

  alias SpriteDiff.{API, Manifest, Diff, Formatter, Agent}

  def main(args) do
    args
    |> parse_args()
    |> run()
  end

  defp parse_args(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          help: :boolean,
          json: :boolean,
          summary: :boolean,
          output: :string,
          file: :string
        ],
        aliases: [h: :help, j: :json, s: :summary, o: :output, f: :file]
      )

    {opts, args}
  end

  defp run({_opts, ["help" | _]}) do
    print_help()
  end

  defp run({opts, []}) do
    if opts[:help] do
      print_help()
    else
      print_help()
      System.halt(1)
    end
  end

  defp run({opts, ["checkpoints", sprite_name]}) do
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

  defp run({opts, ["manifest", sprite_name, checkpoint_id]}) do
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

  defp run({opts, ["diff", sprite_name, checkpoint_a, checkpoint_b]}) do
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

  defp run({opts, ["file", sprite_name, checkpoint_a, checkpoint_b, file_path]}) do
    IO.puts("Diffing #{file_path}...")

    case Diff.file_diff(sprite_name, checkpoint_a, checkpoint_b, file_path) do
      {:ok, content_diff} ->
        Formatter.print_file_diff(file_path, content_diff)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({_opts, ["agent", "install", sprite_name]}) do
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

  defp run({_opts, ["agent", "status", sprite_name]}) do
    case Agent.status(sprite_name) do
      {:ok, status} ->
        Formatter.print_agent_status(status)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({_opts, ["agent", "uninstall", sprite_name]}) do
    IO.puts("Uninstalling sprite-diff agent from #{sprite_name}...")

    case Agent.uninstall(sprite_name) do
      :ok ->
        IO.puts("Agent uninstalled successfully.")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({_opts, ["agent", "trigger", sprite_name]}) do
    IO.puts("Triggering manifest creation on #{sprite_name}...")

    case Agent.trigger_manifest(sprite_name) do
      {:ok, manifest_path} ->
        IO.puts("Manifest created: #{manifest_path}")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({_opts, _args}) do
    print_help()
    System.halt(1)
  end

  defp print_help do
    IO.puts("""
    sprite-diff - Compare Sprites checkpoints

    USAGE:
      sprite-diff <command> [options]

    COMMANDS:
      checkpoints <sprite>                         List all checkpoints
      manifest <sprite> <checkpoint>               Generate manifest for checkpoint
      diff <sprite> <checkpoint-a> <checkpoint-b>  Compare two checkpoints
      file <sprite> <cp-a> <cp-b> <path>           Show file content diff

      agent install <sprite>                       Install manifest agent
      agent status <sprite>                        Check agent status
      agent uninstall <sprite>                     Remove manifest agent
      agent trigger <sprite>                       Manually create manifest

    OPTIONS:
      -h, --help      Show this help
      -j, --json      Output as JSON
      -s, --summary   Show only summary (for diff)
      -o, --output    Write output to file

    ENVIRONMENT:
      SPRITES_TOKEN   API token for authentication (required)
      SPRITES_API_URL API base URL (default: https://api.sprites.dev)

    EXAMPLES:
      sprite-diff checkpoints my-app
      sprite-diff diff my-app checkpoint-1 checkpoint-2
      sprite-diff diff my-app checkpoint-1 checkpoint-2 --json
      sprite-diff file my-app checkpoint-1 checkpoint-2 /app/lib/module.ex
    """)
  end
end
