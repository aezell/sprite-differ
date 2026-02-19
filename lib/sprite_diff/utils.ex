defmodule SpriteDiff.Utils do
  @moduledoc """
  Shared utility functions used across sprite-diff modules.
  """

  @doc """
  Format a byte count into a human-readable string (B, KB, MB, GB).
  """
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_bytes(_), do: "0 B"

  @doc """
  Generate a timestamp-based checkpoint ID.
  """
  def generate_checkpoint_id do
    {{y, m, d}, {h, min, s}} = :calendar.universal_time()

    :io_lib.format("~4..0B~2..0B~2..0BT~2..0B~2..0B~2..0BZ", [y, m, d, h, min, s])
    |> IO.iodata_to_binary()
  end
end
