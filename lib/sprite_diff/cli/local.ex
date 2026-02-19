defmodule SpriteDiff.CLI.Local do
  @moduledoc """
  CLI handlers for local commands: manifest, list, diff.
  """

  alias SpriteDiff.{Diff, Formatter, Utils}

  def run(opts, ["local", "diff", manifest_a_path, manifest_b_path]) do
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

  def run(opts, ["local", "manifest"]) do
    run(opts, ["local", "manifest", Utils.generate_checkpoint_id()])
  end

  def run(opts, ["local", "manifest", checkpoint_id]) do
    base_path = opts[:path] || "/home"
    IO.puts("Creating local manifest: #{checkpoint_id}")
    IO.puts("Scanning: #{base_path}")

    case SpriteDiff.Manifest.generate_local(checkpoint_id, base_path) do
      {:ok, manifest} ->
        manifest_dir = "/.sprite-diff/manifests"
        File.mkdir_p!(manifest_dir)
        manifest_path = "#{manifest_dir}/#{checkpoint_id}.json"

        case opts[:output] do
          nil ->
            File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
            IO.puts("Manifest saved: #{manifest_path}")
            IO.puts("Files scanned: #{manifest["total_files"]}")
            IO.puts("Total size: #{Utils.format_bytes(manifest["total_size"])}")

          path ->
            File.write!(path, Jason.encode!(manifest, pretty: true))
            IO.puts("Manifest saved: #{path}")
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  def run(_opts, ["local", "list"]) do
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
            IO.puts("  #{String.pad_trailing(file, 40)} #{Utils.format_bytes(size)}  #{time}")
          end)
        end

      {:error, :enoent} ->
        IO.puts("No manifests directory found. Run 'sprite-differ local manifest' first.")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
