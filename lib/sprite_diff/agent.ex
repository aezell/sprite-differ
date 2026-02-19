defmodule SpriteDiff.Agent do
  @moduledoc """
  Manages the sprite-diff agent that runs inside a sprite.

  The agent is a lightweight script that:
  - Creates filesystem manifests automatically when triggered
  - Stores manifests in /.sprite-diff/manifests/
  - Can cache file contents for historical checkpoints
  """

  alias SpriteDiff.{API, Utils}

  @agent_dir "/.sprite-diff"
  @manifests_dir "/.sprite-diff/manifests"
  @agent_script "/.sprite-diff/agent.sh"
  @agent_service "/.sprite-diff/sprite-diff-agent.service"

  @doc """
  Install the sprite-diff agent on a sprite.
  """
  def install(sprite_name) do
    with :ok <- create_directories(sprite_name),
         :ok <- install_agent_script(sprite_name),
         :ok <- install_systemd_service(sprite_name),
         :ok <- enable_service(sprite_name) do
      :ok
    end
  end

  @doc """
  Check the status of the agent on a sprite.
  """
  def status(sprite_name) do
    with {:ok, %{exit_code: 0, stdout: installed}} <- API.exec(sprite_name, "test -f #{@agent_script} && echo 'yes' || echo 'no'"),
         {:ok, %{stdout: manifests_output}} <- API.exec(sprite_name, "ls -la #{@manifests_dir} 2>/dev/null | wc -l"),
         {:ok, %{stdout: disk_usage}} <- API.exec(sprite_name, "du -sh #{@agent_dir} 2>/dev/null | cut -f1") do
      manifest_count =
        case Integer.parse(String.trim(manifests_output)) do
          {n, _} when n > 1 -> n - 1  # Subtract 1 for the 'total' line
          _ -> 0
        end

      {:ok, %{
        installed: String.trim(installed) == "yes",
        manifest_count: manifest_count,
        disk_usage: String.trim(disk_usage),
        agent_dir: @agent_dir
      }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Failed to check agent status"}
    end
  end

  @doc """
  Uninstall the agent from a sprite.
  """
  def uninstall(sprite_name) do
    commands = """
    systemctl --user stop sprite-diff-agent 2>/dev/null || true
    systemctl --user disable sprite-diff-agent 2>/dev/null || true
    rm -f ~/.config/systemd/user/sprite-diff-agent.service 2>/dev/null || true
    rm -rf #{@agent_dir}
    """

    case API.exec(sprite_name, commands) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{stderr: stderr}} -> {:error, stderr}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Trigger immediate manifest creation.
  """
  def trigger_manifest(sprite_name, checkpoint_id \\ nil) do
    id = checkpoint_id || Utils.generate_checkpoint_id()

    case API.exec(sprite_name, "#{@agent_script} create-manifest #{id}", timeout: 120_000) do
      {:ok, %{exit_code: 0}} ->
        manifest_path = "#{@manifests_dir}/#{id}.json"
        {:ok, manifest_path}

      {:ok, %{exit_code: code, stderr: stderr}} ->
        {:error, "Manifest creation failed (exit #{code}): #{stderr}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_directories(sprite_name) do
    commands = """
    mkdir -p #{@manifests_dir}
    mkdir -p #{@agent_dir}/files
    chmod 755 #{@agent_dir}
    """

    case API.exec(sprite_name, commands) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{stderr: stderr}} -> {:error, "Failed to create directories: #{stderr}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp install_agent_script(sprite_name) do
    script = agent_script_content()

    with :ok <- API.write_file(sprite_name, @agent_script, script),
         {:ok, %{exit_code: 0}} <- API.exec(sprite_name, "chmod +x #{@agent_script}") do
      :ok
    else
      {:error, reason} -> {:error, "Failed to install agent script: #{reason}"}
      _ -> {:error, "Failed to install agent script"}
    end
  end

  defp install_systemd_service(sprite_name) do
    service = systemd_service_content()

    commands = """
    mkdir -p ~/.config/systemd/user
    """

    with {:ok, %{exit_code: 0}} <- API.exec(sprite_name, commands),
         :ok <- API.write_file(sprite_name, "~/.config/systemd/user/sprite-diff-agent.service", service) do
      :ok
    else
      {:error, reason} -> {:error, "Failed to install systemd service: #{reason}"}
      _ -> {:error, "Failed to install systemd service"}
    end
  end

  defp enable_service(sprite_name) do
    # Note: systemd user services may not be available in all sprite environments
    # This is optional - the agent works without it via manual triggers
    API.exec(sprite_name, "systemctl --user daemon-reload 2>/dev/null || true")
    :ok
  end

  defp agent_script_content do
    ~S"""
#!/bin/bash
# sprite-diff agent - Creates filesystem manifests for checkpoint diffing

set -e

AGENT_DIR="/.sprite-diff"
MANIFESTS_DIR="$AGENT_DIR/manifests"
BASE_PATH="${SPRITE_DIFF_BASE_PATH:-/home}"

# Directories to exclude from manifest
EXCLUDES=(
    "/proc"
    "/sys"
    "/dev"
    "/run"
    "/tmp"
    "/var/cache"
    "/var/log"
    "/.sprite-diff"
    "/var/tmp"
    "*.pyc"
    "__pycache__"
    "node_modules"
    ".git/objects"
)

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  create-manifest [checkpoint-id]  Create a new manifest"
    echo "  list-manifests                   List all manifests"
    echo "  cleanup [days]                   Remove manifests older than N days"
    echo ""
}

build_excludes() {
    local excludes=""
    for excl in "${EXCLUDES[@]}"; do
        excludes="$excludes -path '$excl' -prune -o"
    done
    echo "$excludes"
}

create_manifest() {
    local checkpoint_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
    local manifest_file="$MANIFESTS_DIR/$checkpoint_id.json"
    local temp_file=$(mktemp)

    echo "Creating manifest for checkpoint: $checkpoint_id"
    echo "Scanning from: $BASE_PATH"

    # Start JSON
    echo "{" > "$temp_file"
    echo "  \"checkpoint_id\": \"$checkpoint_id\"," >> "$temp_file"
    echo "  \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$temp_file"
    echo "  \"base_path\": \"$BASE_PATH\"," >> "$temp_file"
    echo "  \"files\": [" >> "$temp_file"

    local first=true
    local file_count=0
    local total_size=0

    # Find all files and generate entries
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
            local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            local mode=$(stat -c %a "$file" 2>/dev/null || echo "644")
            local hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "")

            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$temp_file"
            fi

            cat >> "$temp_file" << ENTRY
    {
      "path": "$file",
      "type": "file",
      "size": $size,
      "mtime": $mtime,
      "mode": "$mode",
      "sha256": "$hash"
    }
ENTRY
            file_count=$((file_count + 1))
            total_size=$((total_size + size))
        fi
    done < <(find "$BASE_PATH" -type f -print0 2>/dev/null)

    # Close files array
    echo "" >> "$temp_file"
    echo "  ]," >> "$temp_file"
    echo "  \"total_files\": $file_count," >> "$temp_file"
    echo "  \"total_size\": $total_size" >> "$temp_file"
    echo "}" >> "$temp_file"

    # Move to final location
    mv "$temp_file" "$manifest_file"
    chmod 644 "$manifest_file"

    echo "Manifest created: $manifest_file"
    echo "Files scanned: $file_count"
    echo "Total size: $total_size bytes"
}

list_manifests() {
    echo "Manifests in $MANIFESTS_DIR:"
    echo ""
    if [ -d "$MANIFESTS_DIR" ]; then
        ls -lh "$MANIFESTS_DIR"/*.json 2>/dev/null || echo "No manifests found."
    else
        echo "Manifest directory does not exist."
    fi
}

cleanup_manifests() {
    local days="${1:-30}"
    echo "Removing manifests older than $days days..."
    find "$MANIFESTS_DIR" -name "*.json" -mtime "+$days" -delete 2>/dev/null
    echo "Cleanup complete."
}

# Main
case "${1:-}" in
    create-manifest)
        create_manifest "$2"
        ;;
    list-manifests)
        list_manifests
        ;;
    cleanup)
        cleanup_manifests "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac
"""
  end

  defp systemd_service_content do
    """
[Unit]
Description=Sprite Diff Agent
After=network.target

[Service]
Type=oneshot
ExecStart=/.sprite-diff/agent.sh create-manifest
RemainAfterExit=no

[Install]
WantedBy=default.target
"""
  end
end
