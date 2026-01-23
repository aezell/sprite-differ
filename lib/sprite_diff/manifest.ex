defmodule SpriteDiff.Manifest do
  @moduledoc """
  Generates filesystem manifests for checkpoints.

  A manifest is a complete listing of all files in a sprite's filesystem,
  including paths, sizes, modification times, and content hashes.
  """

  alias SpriteDiff.API

  @manifest_dir "/.sprite-diff/manifests"
  @default_excludes [
    "/proc",
    "/sys",
    "/dev",
    "/run",
    "/tmp",
    "/var/cache",
    "/var/log",
    "/.sprite-diff"
  ]

  @doc """
  Generate a manifest for a checkpoint.

  First checks for a cached manifest from the agent.
  Falls back to live generation if not found.
  """
  def generate(sprite_name, checkpoint_id, opts \\ []) do
    case get_cached_manifest(sprite_name, checkpoint_id) do
      {:ok, manifest} ->
        {:ok, manifest}

      {:error, _} ->
        generate_live(sprite_name, checkpoint_id, opts)
    end
  end

  @doc """
  Check for a cached manifest created by the agent.
  """
  def get_cached_manifest(sprite_name, checkpoint_id) do
    manifest_path = "#{@manifest_dir}/#{checkpoint_id}.json"

    case API.read_file(sprite_name, manifest_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} -> {:ok, manifest}
          {:error, _} -> {:error, "Invalid manifest JSON"}
        end

      {:error, _} ->
        {:error, "No cached manifest found"}
    end
  end

  @doc """
  Generate a manifest by scanning the live filesystem.
  """
  def generate_live(sprite_name, checkpoint_id, opts \\ []) do
    base_path = Keyword.get(opts, :base_path, "/home")
    excludes = Keyword.get(opts, :excludes, @default_excludes)

    exclude_args =
      excludes
      |> Enum.map(&"-path '#{&1}' -prune -o")
      |> Enum.join(" ")

    # Build find command to get file info
    find_cmd = """
    find #{base_path} #{exclude_args} -type f -print0 2>/dev/null | \
    xargs -0 -I{} sh -c 'stat -c "%n|%s|%Y|%a" "{}" 2>/dev/null && sha256sum "{}" 2>/dev/null | cut -d" " -f1' | \
    paste - - 2>/dev/null
    """

    # Also get directories
    dir_cmd = """
    find #{base_path} #{exclude_args} -type d -print0 2>/dev/null | \
    xargs -0 -I{} stat -c "%n|%s|%Y|%a|dir" "{}" 2>/dev/null
    """

    with {:ok, %{exit_code: 0, stdout: file_output}} <- API.exec(sprite_name, find_cmd, timeout: 120_000),
         {:ok, %{exit_code: 0, stdout: dir_output}} <- API.exec(sprite_name, dir_cmd, timeout: 60_000) do
      files = parse_file_output(file_output)
      dirs = parse_dir_output(dir_output)

      manifest = %{
        "checkpoint_id" => checkpoint_id,
        "sprite" => sprite_name,
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "base_path" => base_path,
        "files" => files ++ dirs,
        "total_files" => length(files),
        "total_dirs" => length(dirs),
        "total_size" => Enum.reduce(files, 0, fn f, acc -> acc + (f["size"] || 0) end)
      }

      {:ok, manifest}
    else
      {:ok, %{exit_code: code, stderr: stderr}} ->
        {:error, "Command failed (exit #{code}): #{stderr}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Save a manifest to the sprite's manifest directory.
  """
  def save_manifest(sprite_name, manifest) do
    checkpoint_id = manifest["checkpoint_id"]
    manifest_path = "#{@manifest_dir}/#{checkpoint_id}.json"

    # Ensure directory exists
    API.exec(sprite_name, "mkdir -p #{@manifest_dir}")

    # Write manifest
    content = Jason.encode!(manifest, pretty: true)
    API.write_file(sprite_name, manifest_path, content)
  end

  @doc """
  List all cached manifests for a sprite.
  """
  def list_cached_manifests(sprite_name) do
    case API.exec(sprite_name, "ls -1 #{@manifest_dir}/*.json 2>/dev/null") do
      {:ok, %{exit_code: 0, stdout: output}} ->
        manifests =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(fn path ->
            checkpoint_id = Path.basename(path, ".json")
            %{"checkpoint_id" => checkpoint_id, "path" => path}
          end)

        {:ok, manifests}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Generate a manifest locally without using the API.
  Scans the local filesystem directly.
  """
  def generate_local(checkpoint_id, base_path \\ "/home", opts \\ []) do
    excludes = Keyword.get(opts, :excludes, @default_excludes)

    try do
      files =
        base_path
        |> scan_directory(excludes)
        |> Enum.map(&get_file_info/1)
        |> Enum.reject(&is_nil/1)

      total_size = Enum.reduce(files, 0, fn f, acc -> acc + (f["size"] || 0) end)

      manifest = %{
        "checkpoint_id" => checkpoint_id,
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "base_path" => base_path,
        "files" => files,
        "total_files" => length(files),
        "total_size" => total_size
      }

      {:ok, manifest}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp scan_directory(path, excludes) do
    if should_exclude?(path, excludes) do
      []
    else
      case File.ls(path) do
        {:ok, entries} ->
          entries
          |> Enum.flat_map(fn entry ->
            full_path = Path.join(path, entry)

            cond do
              should_exclude?(full_path, excludes) ->
                []

              File.dir?(full_path) ->
                scan_directory(full_path, excludes)

              File.regular?(full_path) ->
                [full_path]

              true ->
                []
            end
          end)

        {:error, _} ->
          []
      end
    end
  end

  defp should_exclude?(path, excludes) do
    Enum.any?(excludes, fn exclude ->
      String.starts_with?(path, exclude) or
        String.contains?(path, "/node_modules/") or
        String.contains?(path, "/__pycache__/") or
        String.ends_with?(path, ".pyc")
    end)
  end

  defp get_file_info(path) do
    try do
      stat = File.stat!(path)
      hash = compute_sha256(path)

      %{
        "path" => path,
        "type" => "file",
        "size" => stat.size,
        "mtime" => stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601(),
        "mode" => Integer.to_string(stat.mode, 8) |> String.slice(-3, 3),
        "sha256" => hash
      }
    rescue
      _ -> nil
    end
  end

  defp compute_sha256(path) do
    case File.read(path) do
      {:ok, content} ->
        :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      {:error, _} ->
        nil
    end
  end

  defp parse_file_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_file_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_file_line(line) do
    case String.split(line, "|") do
      [path, size, mtime, mode, hash] ->
        %{
          "path" => String.trim(path),
          "type" => "file",
          "size" => parse_int(size),
          "mtime" => parse_timestamp(mtime),
          "mode" => String.trim(mode),
          "sha256" => String.trim(hash)
        }

      [path, size, mtime, mode] ->
        # No hash (possibly binary read error)
        %{
          "path" => String.trim(path),
          "type" => "file",
          "size" => parse_int(size),
          "mtime" => parse_timestamp(mtime),
          "mode" => String.trim(mode),
          "sha256" => nil
        }

      _ ->
        nil
    end
  end

  defp parse_dir_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_dir_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_dir_line(line) do
    case String.split(line, "|") do
      [path, _size, mtime, mode, "dir"] ->
        %{
          "path" => String.trim(path),
          "type" => "directory",
          "mtime" => parse_timestamp(mtime),
          "mode" => String.trim(mode)
        }

      _ ->
        nil
    end
  end

  defp parse_int(str) do
    case Integer.parse(String.trim(str)) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_timestamp(str) do
    case Integer.parse(String.trim(str)) do
      {unix, _} ->
        DateTime.from_unix!(unix) |> DateTime.to_iso8601()

      :error ->
        nil
    end
  end
end
