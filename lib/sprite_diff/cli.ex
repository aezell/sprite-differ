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
          file: :string,
          path: :string
        ],
        aliases: [h: :help, j: :json, s: :summary, o: :output, f: :file, p: :path]
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

  # Local commands - no API needed

  defp run({opts, ["local", "diff", manifest_a_path, manifest_b_path]}) do
    with {:ok, content_a} <- File.read(manifest_a_path),
         {:ok, content_b} <- File.read(manifest_b_path),
         {:ok, manifest_a} <- Jason.decode(content_a),
         {:ok, manifest_b} <- Jason.decode(content_b) do
      diff_result = Diff.compare_manifests(manifest_a, manifest_b)

      if opts[:json] do
        IO.puts(Jason.encode!(diff_result, pretty: true))
      else
        if opts[:summary] do
          Formatter.print_diff_summary(diff_result)
        else
          Formatter.print_diff(diff_result)
        end
      end
    else
      {:error, :enoent} ->
        IO.puts(:stderr, "Error: Manifest file not found")
        System.halt(1)

      {:error, %Jason.DecodeError{}} ->
        IO.puts(:stderr, "Error: Invalid JSON in manifest file")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run({opts, ["local", "manifest"]}) do
    run({opts, ["local", "manifest", generate_checkpoint_id()]})
  end

  defp run({opts, ["local", "manifest", checkpoint_id]}) do
    base_path = opts[:path] || "/home"
    IO.puts("Creating local manifest: #{checkpoint_id}")
    IO.puts("Scanning: #{base_path}")

    case Manifest.generate_local(checkpoint_id, base_path) do
      {:ok, manifest} ->
        manifest_dir = "/.sprite-diff/manifests"
        File.mkdir_p!(manifest_dir)
        manifest_path = "#{manifest_dir}/#{checkpoint_id}.json"

        case opts[:output] do
          nil ->
            File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
            IO.puts("Manifest saved: #{manifest_path}")
            IO.puts("Files scanned: #{manifest["total_files"]}")
            IO.puts("Total size: #{format_bytes(manifest["total_size"])}")

          path ->
            File.write!(path, Jason.encode!(manifest, pretty: true))
            IO.puts("Manifest saved: #{path}")
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({_opts, ["local", "list"]}) do
    manifest_dir = "/.sprite-diff/manifests"

    case File.ls(manifest_dir) do
      {:ok, files} ->
        manifests = files |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort()

        if manifests == [] do
          IO.puts("No manifests found in #{manifest_dir}")
        else
          IO.puts("Manifests in #{manifest_dir}:\n")
          Enum.each(manifests, fn file ->
            path = Path.join(manifest_dir, file)
            %{size: size, mtime: mtime} = File.stat!(path)
            time = mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_string()
            IO.puts("  #{String.pad_trailing(file, 40)} #{format_bytes(size)}  #{time}")
          end)
        end

      {:error, :enoent} ->
        IO.puts("No manifests directory found. Run 'sprite-differ local manifest' first.")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run({_opts, _args}) do
    print_help()
    System.halt(1)
  end

  defp generate_checkpoint_id do
    {{y, m, d}, {h, min, s}} = :calendar.universal_time()
    :io_lib.format("~4..0B~2..0B~2..0BT~2..0B~2..0B~2..0BZ", [y, m, d, h, min, s])
    |> IO.iodata_to_binary()
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end
  defp format_bytes(_), do: "0 B"

  defp print_help do
    IO.puts("""
    sprite-differ - Compare Sprites checkpoints

    USAGE:
      sprite-differ <command> [options]

    LOCAL COMMANDS (no API token needed):
      local manifest [checkpoint-id]               Create manifest of current filesystem
      local list                                   List local manifests
      local diff <manifest-a> <manifest-b>         Compare two manifest files

    REMOTE COMMANDS (requires SPRITES_TOKEN):
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
      -p, --path      Base path to scan (default: /home)

    ENVIRONMENT:
      SPRITES_TOKEN   API token for remote commands
      SPRITES_API_URL API base URL (default: https://api.sprites.dev)

    EXAMPLES:
      # Local usage (on a sprite):
      sprite-differ local manifest before-changes
      sprite-differ local manifest after-changes
      sprite-differ local diff /.sprite-diff/manifests/before-changes.json \\
                               /.sprite-diff/manifests/after-changes.json

      # Remote usage (with API):
      sprite-differ checkpoints my-app
      sprite-differ diff my-app checkpoint-1 checkpoint-2
    """)
  end
end
