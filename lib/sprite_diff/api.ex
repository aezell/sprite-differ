defmodule SpriteDiff.API do
  @moduledoc """
  Client for the Sprites API.
  """

  @default_api_url "https://api.sprites.dev"

  def api_url do
    System.get_env("SPRITES_API_URL", @default_api_url)
  end

  def token do
    System.get_env("SPRITES_TOKEN")
  end

  def list_sprites do
    case get("/v1/sprites") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body["sprites"] || body}

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def list_checkpoints(sprite_name) do
    case get("/v1/sprites/#{sprite_name}/checkpoints") do
      {:ok, %{status: 200, body: body}} ->
        checkpoints =
          (body["checkpoints"] || body)
          |> Enum.map(&normalize_checkpoint/1)
          |> Enum.sort_by(& &1["created_at"], :desc)

        {:ok, checkpoints}

      {:ok, %{status: 404}} ->
        {:error, "Sprite '#{sprite_name}' not found"}

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def get_checkpoint(sprite_name, checkpoint_id) do
    case get("/v1/sprites/#{sprite_name}/checkpoints/#{checkpoint_id}") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, normalize_checkpoint(body)}

      {:ok, %{status: 404}} ->
        {:error, "Checkpoint '#{checkpoint_id}' not found"}

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def restore_checkpoint(sprite_name, checkpoint_id) do
    case post("/v1/sprites/#{sprite_name}/checkpoints/#{checkpoint_id}/restore", %{}) do
      {:ok, %{status: status}} when status in [200, 201, 204] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Restore failed with #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def exec(sprite_name, command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    body = %{
      command: command,
      timeout: timeout
    }

    case post("/v1/sprites/#{sprite_name}/exec", body, receive_timeout: timeout + 5_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{
          stdout: body["stdout"] || "",
          stderr: body["stderr"] || "",
          exit_code: body["exit_code"] || body["exitCode"] || 0
        }}

      {:ok, %{status: status, body: body}} ->
        {:error, "Exec failed with #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def upload_file(sprite_name, local_path, remote_path) do
    content = File.read!(local_path)
    write_file(sprite_name, remote_path, content)
  end

  def write_file(sprite_name, remote_path, content) do
    encoded = Base.encode64(content)
    command = "echo '#{encoded}' | base64 -d > '#{remote_path}'"

    case exec(sprite_name, command) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{stderr: stderr}} -> {:error, stderr}
      error -> error
    end
  end

  def read_file(sprite_name, remote_path) do
    case exec(sprite_name, "cat '#{remote_path}'") do
      {:ok, %{exit_code: 0, stdout: content}} ->
        {:ok, content}

      {:ok, %{exit_code: _, stderr: stderr}} ->
        {:error, String.trim(stderr)}

      error ->
        error
    end
  end

  defp get(path, opts \\ []) do
    request(:get, path, nil, opts)
  end

  defp post(path, body, opts \\ []) do
    request(:post, path, body, opts)
  end

  defp request(method, path, body, opts) do
    token = token()

    if is_nil(token) or token == "" do
      {:error, "SPRITES_TOKEN environment variable not set"}
    else
      url = api_url() <> path

      req_opts =
        [
          method: method,
          url: url,
          headers: [
            {"authorization", "Bearer #{token}"},
            {"content-type", "application/json"},
            {"accept", "application/json"}
          ],
          receive_timeout: Keyword.get(opts, :receive_timeout, 30_000)
        ]
        |> maybe_add_body(body)

      case Req.request(req_opts) do
        {:ok, response} ->
          {:ok, %{status: response.status, body: response.body}}

        {:error, exception} ->
          {:error, Exception.message(exception)}
      end
    end
  end

  defp maybe_add_body(opts, nil), do: opts
  defp maybe_add_body(opts, body), do: Keyword.put(opts, :json, body)

  defp normalize_checkpoint(cp) when is_map(cp) do
    %{
      "id" => cp["id"] || cp["checkpoint_id"] || cp["name"],
      "created_at" => cp["created_at"] || cp["createdAt"] || cp["timestamp"],
      "size" => cp["size"] || cp["size_bytes"],
      "trigger" => cp["trigger"] || cp["trigger_type"] || "manual",
      "name" => cp["name"] || cp["label"]
    }
  end
end
