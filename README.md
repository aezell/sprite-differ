# sprite-diff

Compare Sprites checkpoints to see what changed between any two points in time.

## Overview

sprite-diff solves the problem of opaque checkpoints. Instead of guessing what changed between checkpoint-7 and checkpoint-12, you can see exactly which files were added, modified, or deleted.

**Key features:**
- List and inspect checkpoints with metadata
- Generate filesystem manifests (file paths, sizes, hashes)
- Compare manifests to produce detailed diffs
- View file-level content diffs with syntax highlighting
- Install an agent for automatic manifest creation

## Installation

### Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- A Sprites API token

### Build from source

```bash
git clone https://github.com/aezell/sprite-differ
cd sprite-differ/sprite_diff

# Install dependencies
mix deps.get

# Build the CLI
mix escript.build

# Optional: install to your PATH
cp sprite_diff ~/.local/bin/sprite-diff
```

## Configuration

Set your Sprites API token:

```bash
export SPRITES_TOKEN=your_api_token_here
```

Optionally set a custom API URL:

```bash
export SPRITES_API_URL=https://api.sprites.dev  # default
```

## Usage

### List checkpoints

```bash
sprite-diff checkpoints my-sprite
```

Output:
```
CHECKPOINTS FOR my-sprite
──────────────────────────────────────────────────────────────────────
ID                                  CREATED               SIZE
──────────────────────────────────────────────────────────────────────
checkpoint-2025-01-20-pm            2025-01-20 14:30      52.3 MB
checkpoint-2025-01-20-am            2025-01-20 09:00      51.8 MB
checkpoint-2025-01-19               2025-01-19 17:00      51.2 MB
──────────────────────────────────────────────────────────────────────
```

### Compare two checkpoints

```bash
sprite-diff diff my-sprite checkpoint-2025-01-19 checkpoint-2025-01-20-pm
```

Output:
```
COMPARING checkpoint-2025-01-19 → checkpoint-2025-01-20-pm
────────────────────────────────────────────────────────────

SUMMARY
  Files changed:  47
  Files added:    12
  Files modified: 23
  Files deleted:  3

  Size delta:     +1.1 MB
  Similarity:     94.2%

CHANGES
  A  lib/my_app/billing.ex            +156
  A  lib/my_app/billing/invoice.ex    +89
  M  lib/my_app/accounts.ex           +45 -12
  M  config/config.exs                +3 -1
  D  lib/my_app/legacy_auth.ex        -203
  ... (41 more files)
```

### View file content diff

```bash
sprite-diff file my-sprite checkpoint-a checkpoint-b lib/my_app/accounts.ex
```

Output:
```
── lib/my_app/accounts.ex ──
+18 -3

@@ -15,+15 @@
 def get_user(id) do
   Repo.get(User, id)
 end
+
+def get_user_with_billing(id) do
+  User
+  |> where([u], u.id == ^id)
+  |> preload(:invoices)
+  |> Repo.one()
+end
```

### JSON output

Add `--json` to any command for machine-readable output:

```bash
sprite-diff checkpoints my-sprite --json
sprite-diff diff my-sprite cp-a cp-b --json
```

## Agent Installation

The agent creates manifests automatically, making diffs fast and non-disruptive.

### Install the agent on a sprite

```bash
sprite-diff agent install my-sprite
```

This installs a lightweight bash script at `/.sprite-diff/agent.sh` that:
- Scans the filesystem and records file metadata
- Computes SHA256 hashes for change detection
- Stores manifests in `/.sprite-diff/manifests/`

### Check agent status

```bash
sprite-diff agent status my-sprite
```

### Manually trigger a manifest

```bash
sprite-diff agent trigger my-sprite
```

### Uninstall the agent

```bash
sprite-diff agent uninstall my-sprite
```

## Local Usage (without API)

You can run the agent directly on a sprite without the API:

```bash
# Create the agent directory
sudo mkdir -p /.sprite-diff/manifests

# Copy the agent script (or create it manually)
# Then create manifests directly:
/.sprite-diff/agent.sh create-manifest checkpoint-1

# Make some changes...

/.sprite-diff/agent.sh create-manifest checkpoint-2

# List manifests
/.sprite-diff/agent.sh list-manifests
```

## Manifest Format

Manifests are JSON files containing:

```json
{
  "checkpoint_id": "checkpoint-2025-01-20T12:00:00Z",
  "created_at": "2025-01-20T12:00:00Z",
  "base_path": "/home",
  "files": [
    {
      "path": "/home/user/app/lib/my_app.ex",
      "type": "file",
      "size": 2048,
      "mtime": 1705752900,
      "mode": "644",
      "sha256": "abc123..."
    }
  ],
  "total_files": 1247,
  "total_size": 52428800
}
```

## Diff Output Format

```json
{
  "checkpoint_a": "checkpoint-2025-01-19",
  "checkpoint_b": "checkpoint-2025-01-20",
  "summary": {
    "files_added": 5,
    "files_modified": 23,
    "files_deleted": 2,
    "bytes_added": 15360,
    "bytes_removed": 4096,
    "similarity_score": 0.94
  },
  "changes": [
    {
      "path": "/home/user/app/lib/my_app.ex",
      "status": "modified",
      "size_before": 1024,
      "size_after": 2048,
      "sha256_before": "abc...",
      "sha256_after": "def..."
    }
  ]
}
```

## Command Reference

```
sprite-diff <command> [options]

COMMANDS:
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
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     SPRITE-DIFF CLI                         │
│                                                             │
│  • checkpoints    • manifest    • diff    • agent           │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
┌───────────────────┐     ┌───────────────────┐
│   SPRITES API     │     │   SPRITE AGENT    │
│                   │     │                   │
│ • List checkpoints│     │ • Create manifest │
│ • Exec commands   │     │ • Store in        │
│                   │     │   /.sprite-diff/  │
└───────────────────┘     └───────────────────┘
```

## Development

```bash
# Run tests
mix test

# Run with IEx
iex -S mix

# Use programmatically
{:ok, checkpoints} = SpriteDiff.list_checkpoints("my-sprite")
{:ok, diff} = SpriteDiff.compare("my-sprite", "cp-1", "cp-2")
```

## License

MIT
