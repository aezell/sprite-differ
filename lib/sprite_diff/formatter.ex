defmodule SpriteDiff.Formatter do
  @moduledoc """
  Formats output for terminal display.
  """

  # ANSI color codes
  @reset "\e[0m"
  @bold "\e[1m"
  @dim "\e[2m"
  @red "\e[31m"
  @green "\e[32m"
  @yellow "\e[33m"
  @blue "\e[34m"
  @cyan "\e[36m"

  @doc """
  Print a list of checkpoints in a table format.
  """
  def print_checkpoints(checkpoints, sprite_name) do
    IO.puts("")
    IO.puts("#{@bold}CHECKPOINTS FOR #{sprite_name}#{@reset}")
    IO.puts(String.duplicate("─", 70))

    header = String.pad_trailing("ID", 35) <>
             String.pad_trailing("CREATED", 22) <>
             String.pad_leading("SIZE", 12)

    IO.puts("#{@dim}#{header}#{@reset}")
    IO.puts(String.duplicate("─", 70))

    Enum.each(checkpoints, fn cp ->
      id = truncate(cp["id"] || "unknown", 33)
      created = format_datetime(cp["created_at"])
      size = format_bytes(cp["size"])

      IO.puts(
        String.pad_trailing(id, 35) <>
        String.pad_trailing(created, 22) <>
        String.pad_leading(size, 12)
      )
    end)

    IO.puts(String.duplicate("─", 70))
    IO.puts("#{@dim}Total: #{length(checkpoints)} checkpoints#{@reset}")
    IO.puts("")
  end

  @doc """
  Format a manifest for display.
  """
  def format_manifest(manifest) do
    """
    Checkpoint: #{manifest["checkpoint_id"]}
    Created: #{manifest["created_at"]}
    Base Path: #{manifest["base_path"]}
    Total Files: #{manifest["total_files"]}
    Total Size: #{format_bytes(manifest["total_size"])}
    """
  end

  @doc """
  Print a diff summary.
  """
  def print_diff_summary(diff_result) do
    summary = diff_result["summary"]

    IO.puts("")
    IO.puts("#{@bold}COMPARING#{@reset} #{diff_result["checkpoint_a"]} → #{diff_result["checkpoint_b"]}")
    IO.puts(String.duplicate("─", 60))
    IO.puts("")
    IO.puts("#{@bold}SUMMARY#{@reset}")
    IO.puts("  Files changed:  #{summary["total_changes"]}")
    IO.puts("  #{@green}Files added:    #{summary["files_added"]}#{@reset}")
    IO.puts("  #{@yellow}Files modified: #{summary["files_modified"]}#{@reset}")
    IO.puts("  #{@red}Files deleted:  #{summary["files_deleted"]}#{@reset}")
    IO.puts("")
    IO.puts("  Size delta:     #{format_bytes_signed(summary["bytes_delta"])}")
    IO.puts("  Similarity:     #{format_percent(summary["similarity_score"])}")
    IO.puts("")
  end

  @doc """
  Print full diff with file list.
  """
  def print_diff(diff_result) do
    print_diff_summary(diff_result)

    changes = diff_result["changes"]

    if changes == [] do
      IO.puts("#{@dim}No changes detected.#{@reset}")
    else
      IO.puts("#{@bold}CHANGES#{@reset}")

      changes
      |> Enum.take(50)
      |> Enum.each(&print_change/1)

      remaining = length(changes) - 50
      if remaining > 0 do
        IO.puts("  #{@dim}... (#{remaining} more files)#{@reset}")
      end
    end

    IO.puts("")
  end

  defp print_change(change) do
    status_char = case change["status"] do
      "added" -> "#{@green}A#{@reset}"
      "modified" -> "#{@yellow}M#{@reset}"
      "deleted" -> "#{@red}D#{@reset}"
      _ -> " "
    end

    path = change["path"]

    size_info = case change["status"] do
      "added" ->
        "#{@green}+#{format_bytes(change["size_after"])}#{@reset}"

      "deleted" ->
        "#{@red}-#{format_bytes(change["size_before"])}#{@reset}"

      "modified" ->
        delta = (change["size_after"] || 0) - (change["size_before"] || 0)
        if delta >= 0 do
          "#{@yellow}+#{format_bytes(delta)}#{@reset}"
        else
          "#{@yellow}#{format_bytes(delta)}#{@reset}"
        end

      _ ->
        ""
    end

    IO.puts("  #{status_char}  #{truncate(path, 50)}  #{size_info}")
  end

  @doc """
  Print file content diff with syntax highlighting.
  """
  def print_file_diff(filename, diff_result) do
    IO.puts("")
    IO.puts("#{@bold}── #{filename} ──#{@reset}")
    IO.puts("")

    additions = diff_result["additions"] || 0
    deletions = diff_result["deletions"] || 0

    IO.puts("#{@green}+#{additions}#{@reset} #{@red}-#{deletions}#{@reset}")
    IO.puts("")

    hunks = diff_result["hunks"] || []

    Enum.each(hunks, fn hunk ->
      IO.puts("#{@cyan}@@ -#{hunk["start_a"]},+#{hunk["start_b"]} @@#{@reset}")

      (hunk["lines"] || [])
      |> Enum.each(fn line ->
        case line["type"] do
          "add" ->
            IO.puts("#{@green}+#{line["content"]}#{@reset}")

          "delete" ->
            IO.puts("#{@red}-#{line["content"]}#{@reset}")

          "context" ->
            IO.puts(" #{line["content"]}")

          _ ->
            IO.puts(" #{line["content"]}")
        end
      end)

      IO.puts("")
    end)
  end

  @doc """
  Print agent status.
  """
  def print_agent_status(status) do
    IO.puts("")
    IO.puts("#{@bold}SPRITE-DIFF AGENT STATUS#{@reset}")
    IO.puts(String.duplicate("─", 40))

    installed_str = if status.installed do
      "#{@green}Installed#{@reset}"
    else
      "#{@red}Not installed#{@reset}"
    end

    IO.puts("  Status:         #{installed_str}")
    IO.puts("  Agent dir:      #{status.agent_dir}")
    IO.puts("  Manifests:      #{status.manifest_count}")
    IO.puts("  Disk usage:     #{status.disk_usage}")
    IO.puts("")
  end

  # Helper functions

  defp format_datetime(nil), do: "unknown"
  defp format_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} ->
        Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

      _ ->
        String.slice(dt, 0, 19)
    end
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end
  defp format_bytes(_), do: "? B"

  defp format_bytes_signed(nil), do: "0 B"
  defp format_bytes_signed(bytes) when bytes >= 0, do: "+#{format_bytes(bytes)}"
  defp format_bytes_signed(bytes), do: "-#{format_bytes(abs(bytes))}"

  defp format_percent(nil), do: "N/A"
  defp format_percent(score) when is_float(score), do: "#{Float.round(score * 100, 1)}%"
  defp format_percent(_), do: "N/A"

  defp truncate(str, max_len) when byte_size(str) <= max_len, do: str
  defp truncate(str, max_len), do: String.slice(str, 0, max_len - 3) <> "..."
end
