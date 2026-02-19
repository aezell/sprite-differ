defmodule SpriteDiff.Diff do
  @moduledoc """
  Compares two checkpoint manifests and produces diff output.
  """

  alias SpriteDiff.{API, Manifest, TextDiff}

  @doc """
  Compare two checkpoints and return a diff result.
  """
  def compare(sprite_name, checkpoint_a, checkpoint_b) do
    with {:ok, manifest_a} <- Manifest.generate(sprite_name, checkpoint_a),
         {:ok, manifest_b} <- Manifest.generate(sprite_name, checkpoint_b) do
      diff_result = compare_manifests(manifest_a, manifest_b)
      {:ok, diff_result}
    end
  end

  @doc """
  Compare two manifests directly.
  """
  def compare_manifests(manifest_a, manifest_b) do
    files_a = index_by_path(manifest_a["files"] || [])
    files_b = index_by_path(manifest_b["files"] || [])

    paths_a = MapSet.new(Map.keys(files_a))
    paths_b = MapSet.new(Map.keys(files_b))

    added_paths = MapSet.difference(paths_b, paths_a)
    deleted_paths = MapSet.difference(paths_a, paths_b)
    common_paths = MapSet.intersection(paths_a, paths_b)

    added =
      added_paths
      |> Enum.map(fn path ->
        file = files_b[path]
        %{
          "path" => path,
          "status" => "added",
          "type" => file["type"],
          "size_after" => file["size"],
          "sha256_after" => file["sha256"]
        }
      end)
      |> Enum.sort_by(& &1["path"])

    deleted =
      deleted_paths
      |> Enum.map(fn path ->
        file = files_a[path]
        %{
          "path" => path,
          "status" => "deleted",
          "type" => file["type"],
          "size_before" => file["size"],
          "sha256_before" => file["sha256"]
        }
      end)
      |> Enum.sort_by(& &1["path"])

    modified =
      common_paths
      |> Enum.filter(fn path ->
        file_a = files_a[path]
        file_b = files_b[path]
        file_a["type"] == "file" and file_b["type"] == "file" and
          (file_a["sha256"] != file_b["sha256"] or file_a["size"] != file_b["size"])
      end)
      |> Enum.map(fn path ->
        file_a = files_a[path]
        file_b = files_b[path]
        %{
          "path" => path,
          "status" => "modified",
          "type" => "file",
          "size_before" => file_a["size"],
          "size_after" => file_b["size"],
          "sha256_before" => file_a["sha256"],
          "sha256_after" => file_b["sha256"]
        }
      end)
      |> Enum.sort_by(& &1["path"])

    changes = added ++ modified ++ deleted

    bytes_added =
      Enum.reduce(added, 0, fn c, acc -> acc + (c["size_after"] || 0) end) +
        Enum.reduce(modified, 0, fn c, acc ->
          acc + max(0, (c["size_after"] || 0) - (c["size_before"] || 0))
        end)

    bytes_removed =
      Enum.reduce(deleted, 0, fn c, acc -> acc + (c["size_before"] || 0) end) +
        Enum.reduce(modified, 0, fn c, acc ->
          acc + max(0, (c["size_before"] || 0) - (c["size_after"] || 0))
        end)

    total_files_a = length(Enum.filter(manifest_a["files"] || [], &(&1["type"] == "file")))
    total_files_b = length(Enum.filter(manifest_b["files"] || [], &(&1["type"] == "file")))

    similarity = calculate_similarity(files_a, files_b)

    %{
      "checkpoint_a" => manifest_a["checkpoint_id"],
      "checkpoint_b" => manifest_b["checkpoint_id"],
      "summary" => %{
        "files_added" => length(added),
        "files_modified" => length(modified),
        "files_deleted" => length(deleted),
        "total_changes" => length(changes),
        "bytes_added" => bytes_added,
        "bytes_removed" => bytes_removed,
        "bytes_delta" => bytes_added - bytes_removed,
        "total_files_a" => total_files_a,
        "total_files_b" => total_files_b,
        "similarity_score" => similarity
      },
      "changes" => changes
    }
  end

  @doc """
  Get the content diff for a specific file between two checkpoints.
  """
  def file_diff(sprite_name, checkpoint_a, checkpoint_b, file_path) do
    with {:ok, content_a} <- get_file_content(sprite_name, checkpoint_a, file_path),
         {:ok, content_b} <- get_file_content(sprite_name, checkpoint_b, file_path) do
      diff = TextDiff.unified_diff(content_a, content_b, file_path)
      {:ok, diff}
    end
  end

  defp get_file_content(sprite_name, checkpoint_id, file_path) do
    cached_path = "/.sprite-diff/files/#{checkpoint_id}#{file_path}"

    case API.read_file(sprite_name, cached_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, _} ->
        API.read_file(sprite_name, file_path)
    end
  end

  defp calculate_similarity(files_a, files_b) do
    hashes_a = files_a |> Map.values() |> Enum.map(& &1["sha256"]) |> Enum.reject(&is_nil/1) |> MapSet.new()
    hashes_b = files_b |> Map.values() |> Enum.map(& &1["sha256"]) |> Enum.reject(&is_nil/1) |> MapSet.new()

    if MapSet.size(hashes_a) == 0 and MapSet.size(hashes_b) == 0 do
      1.0
    else
      intersection = MapSet.intersection(hashes_a, hashes_b) |> MapSet.size()
      union = MapSet.union(hashes_a, hashes_b) |> MapSet.size()

      if union == 0, do: 1.0, else: Float.round(intersection / union, 4)
    end
  end

  defp index_by_path(files) do
    files
    |> Enum.map(fn file -> {file["path"], file} end)
    |> Map.new()
  end
end
