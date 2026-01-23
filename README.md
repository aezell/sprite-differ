# sprite-differ

Compare Sprites checkpoints to see what changed between any two points in time.

## Overview

sprite-differ solves the problem of opaque checkpoints. Instead of guessing what changed between checkpoint-7 and checkpoint-12, you can see exactly which files were added, modified, or deleted.

**Key features:**
- List and inspect checkpoints with metadata
- Generate filesystem manifests (file paths, sizes, hashes)
- Compare manifests to produce detailed diffs
- View file-level content diffs with syntax highlighting
- Install an agent for automatic manifest creation

## Installation

### Quick install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/aezell/sprite-differ/main/install.sh | bash
```

This downloads the latest pre-built binary for your platform to `~/.local/bin/`.

### Download binary manually

Download the latest release for your platform from [GitHub Releases](https://github.com/aezell/sprite-differ/releases):

| Platform | Download |
|----------|----------|
| Linux x86_64 | `sprite-differ-linux-x86_64` |
| Linux ARM64 | `sprite-differ-linux-aarch64` |
| macOS x86_64 | `sprite-differ-macos-x86_64` |
| macOS ARM64 | `sprite-differ-macos-aarch64` |

```bash
# Example: download and install on Linux x86_64
curl -fsSL https://github.com/aezell/sprite-differ/releases/latest/download/sprite-differ-linux-x86_64 \
  -o ~/.local/bin/sprite-differ
chmod +x ~/.local/bin/sprite-differ
```

### Build from source

Requires Elixir 1.14+ and Erlang/OTP 25+.

```bash
git clone https://github.com/aezell/sprite-differ
cd sprite-differ

# Install dependencies
mix deps.get

# Build the CLI (escript - requires Erlang runtime)
mix escript.build
cp sprite-differ ~/.local/bin/

# Or build standalone binary (no runtime needed)
MIX_ENV=prod mix release sprite_differ
cp burrito_out/sprite_differ_linux_x86_64 ~/.local/bin/sprite-differ
```

## Usage

sprite-differ supports two modes:
- **Local mode** - Run directly on a sprite, no API token needed
- **Remote mode** - Manage sprites remotely via the Sprites API

---

## Local Mode (on a sprite)

No configuration needed. Create manifests and compare them directly on the sprite.

### Create a manifest

```bash
sprite-differ local manifest before-changes
```

Output:
```
Creating local manifest: before-changes
Scanning: /home
Manifest saved: /.sprite-diff/manifests/before-changes.json
Files scanned: 1247
Total size: 52.4 MB
```

### Make changes, then create another manifest

```bash
# ... edit files, install packages, etc ...

sprite-differ local manifest after-changes
```

### Compare the manifests

```bash
sprite-differ local diff \
  /.sprite-diff/manifests/before-changes.json \
  /.sprite-diff/manifests/after-changes.json
```

Output:
```
COMPARING before-changes → after-changes
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
  M  lib/my_app/accounts.ex           +45 -12
  D  lib/my_app/legacy_auth.ex        -203
  ... (more files)
```

### List saved manifests

```bash
sprite-differ local list
```

### Scan a specific directory

```bash
sprite-differ local manifest my-snapshot --path /home/user/myproject
```

### Tip: Auto-manifest before checkpoints

To automatically create a manifest every time you create a checkpoint, add an alias to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
alias checkpoint='sprite-differ local manifest "pre-$(date +%Y%m%d-%H%M%S)" && sprite checkpoint create'
```

Now running `checkpoint` will capture a manifest right before the checkpoint is created.

---

## Remote Mode (via API)

For managing sprites remotely. Requires a Sprites API token.

### Configuration

```bash
export SPRITES_TOKEN=your_api_token_here
export SPRITES_API_URL=https://api.sprites.dev  # optional
```

### List checkpoints

```bash
sprite-differ checkpoints my-sprite
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
sprite-differ diff my-sprite checkpoint-2025-01-19 checkpoint-2025-01-20-pm
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
sprite-differ file my-sprite checkpoint-a checkpoint-b lib/my_app/accounts.ex
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
sprite-differ checkpoints my-sprite --json
sprite-differ diff my-sprite cp-a cp-b --json
```

## Agent Installation

The agent creates manifests automatically, making diffs fast and non-disruptive.

### Install the agent on a sprite

```bash
sprite-differ agent install my-sprite
```

This installs a lightweight bash script at `/.sprite-diff/agent.sh` that:
- Scans the filesystem and records file metadata
- Computes SHA256 hashes for change detection
- Stores manifests in `/.sprite-diff/manifests/`

### Check agent status

```bash
sprite-differ agent status my-sprite
```

### Manually trigger a manifest

```bash
sprite-differ agent trigger my-sprite
```

### Uninstall the agent

```bash
sprite-differ agent uninstall my-sprite
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
sprite-differ <command> [options]

LOCAL COMMANDS (no API token needed):
  local manifest [checkpoint-id]               Create manifest of current filesystem
  local list                                   List saved manifests
  local diff <manifest-a> <manifest-b>         Compare two manifest files

REMOTE COMMANDS (requires SPRITES_TOKEN):
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
  -p, --path      Base path to scan (default: /home)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SPRITE-DIFFER CLI                        │
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
