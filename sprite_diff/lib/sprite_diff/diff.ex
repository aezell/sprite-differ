defmodule SpriteDiff.Diff do
  @moduledoc """
  Compares two checkpoint manifests and produces diff output.
  """

  alias SpriteDiff.{API, Manifest}

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
    # For now, we read the files directly
    # In a production version, we'd need to restore checkpoints
    # or use the agent to fetch file content from cached state

    with {:ok, content_a} <- get_file_content(sprite_name, checkpoint_a, file_path),
         {:ok, content_b} <- get_file_content(sprite_name, checkpoint_b, file_path) do
      diff = unified_diff(content_a, content_b, file_path)
      {:ok, diff}
    end
  end

  defp get_file_content(sprite_name, checkpoint_id, file_path) do
    # First try to get from cached file content
    cached_path = "/.sprite-diff/files/#{checkpoint_id}#{file_path}"

    case API.read_file(sprite_name, cached_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, _} ->
        # Fall back to reading current file (only works if at this checkpoint)
        API.read_file(sprite_name, file_path)
    end
  end

  @doc """
  Generate a unified diff between two strings.
  """
  def unified_diff(content_a, content_b, filename \\ "file") do
    lines_a = String.split(content_a, "\n")
    lines_b = String.split(content_b, "\n")

    hunks = compute_diff_hunks(lines_a, lines_b)

    %{
      "filename" => filename,
      "lines_before" => length(lines_a),
      "lines_after" => length(lines_b),
      "hunks" => hunks,
      "additions" => count_additions(hunks),
      "deletions" => count_deletions(hunks)
    }
  end

  defp compute_diff_hunks(lines_a, lines_b) do
    # Simple LCS-based diff algorithm
    lcs = longest_common_subsequence(lines_a, lines_b)
    build_hunks(lines_a, lines_b, lcs)
  end

  defp longest_common_subsequence(a, b) do
    a_list = Enum.with_index(a)
    b_list = Enum.with_index(b)

    # Build DP table
    table =
      Enum.reduce(a_list, %{}, fn {a_val, i}, acc ->
        Enum.reduce(b_list, acc, fn {b_val, j}, inner_acc ->
          val =
            if a_val == b_val do
              Map.get(inner_acc, {i - 1, j - 1}, 0) + 1
            else
              max(
                Map.get(inner_acc, {i - 1, j}, 0),
                Map.get(inner_acc, {i, j - 1}, 0)
              )
            end

          Map.put(inner_acc, {i, j}, val)
        end)
      end)

    # Backtrack to find LCS
    backtrack_lcs(table, a, b, length(a) - 1, length(b) - 1, [])
  end

  defp backtrack_lcs(_table, _a, _b, i, _j, acc) when i < 0, do: acc
  defp backtrack_lcs(_table, _a, _b, _i, j, acc) when j < 0, do: acc

  defp backtrack_lcs(table, a, b, i, j, acc) do
    a_val = Enum.at(a, i)
    b_val = Enum.at(b, j)

    if a_val == b_val do
      backtrack_lcs(table, a, b, i - 1, j - 1, [{i, j, a_val} | acc])
    else
      if Map.get(table, {i - 1, j}, 0) > Map.get(table, {i, j - 1}, 0) do
        backtrack_lcs(table, a, b, i - 1, j, acc)
      else
        backtrack_lcs(table, a, b, i, j - 1, acc)
      end
    end
  end

  defp build_hunks(lines_a, lines_b, lcs) do
    # Convert LCS to a diff with context
    {hunks, _} = build_hunks_rec(lines_a, lines_b, lcs, 0, 0, [], [])
    Enum.reverse(hunks)
  end

  defp build_hunks_rec(lines_a, lines_b, [], i, j, current_hunk, hunks) do
    # Handle remaining lines
    remaining_a = Enum.slice(lines_a, i..-1//1)
    remaining_b = Enum.slice(lines_b, j..-1//1)

    hunk_lines =
      Enum.map(remaining_a, &%{"type" => "delete", "content" => &1}) ++
        Enum.map(remaining_b, &%{"type" => "add", "content" => &1})

    final_hunk = current_hunk ++ hunk_lines

    if final_hunk == [] do
      {hunks, nil}
    else
      {[%{"lines" => final_hunk, "start_a" => i + 1, "start_b" => j + 1} | hunks], nil}
    end
  end

  defp build_hunks_rec(lines_a, lines_b, [{lcs_i, lcs_j, _line} | rest_lcs], i, j, current_hunk, hunks) do
    # Add deleted lines (in a but before lcs)
    deleted =
      Enum.slice(lines_a, i..(lcs_i - 1)//1)
      |> Enum.map(&%{"type" => "delete", "content" => &1})

    # Add added lines (in b but before lcs)
    added =
      Enum.slice(lines_b, j..(lcs_j - 1)//1)
      |> Enum.map(&%{"type" => "add", "content" => &1})

    # Add context line
    context_line = %{"type" => "context", "content" => Enum.at(lines_a, lcs_i)}

    new_hunk = current_hunk ++ deleted ++ added ++ [context_line]

    # If hunk is getting large, split it
    if length(new_hunk) > 50 and (deleted != [] or added != []) do
      build_hunks_rec(
        lines_a,
        lines_b,
        rest_lcs,
        lcs_i + 1,
        lcs_j + 1,
        [],
        [%{"lines" => new_hunk, "start_a" => i + 1, "start_b" => j + 1} | hunks]
      )
    else
      build_hunks_rec(lines_a, lines_b, rest_lcs, lcs_i + 1, lcs_j + 1, new_hunk, hunks)
    end
  end

  defp count_additions(hunks) do
    Enum.reduce(hunks, 0, fn hunk, acc ->
      acc + Enum.count(hunk["lines"] || [], &(&1["type"] == "add"))
    end)
  end

  defp count_deletions(hunks) do
    Enum.reduce(hunks, 0, fn hunk, acc ->
      acc + Enum.count(hunk["lines"] || [], &(&1["type"] == "delete"))
    end)
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
