defmodule SpriteDiff.TextDiff do
  @moduledoc """
  Text diffing algorithm based on Longest Common Subsequence (LCS).

  Produces unified diff output with hunks showing additions,
  deletions, and context lines between two text contents.
  """

  @doc """
  Generate a unified diff between two strings.

  Returns a map with filename, line counts, hunks, and addition/deletion counts.
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
end
