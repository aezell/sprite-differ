# Checkpoint Diff Viewer

A tool for Sprites users to visualize what changed between any two checkpoints. Makes the unique "time travel" capability of Sprites tangible and useful.

---

## Problem Statement

When working with Sprites, users accumulate checkpoints over time. But checkpoints are opaque—you know *when* they were created but not *what* changed. This leads to:

- **Blind restores** — "I think checkpoint-7 was before I broke everything?"
- **Checkpoint hoarding** — Keeping everything because you can't tell what's safe to delete
- **Debugging friction** — "Something changed between yesterday and today, but what?"
- **Wasted storage** — Many near-identical checkpoints with no way to identify them

A diff viewer solves this by answering: "What's different between checkpoint A and checkpoint B?"

---

## User Stories

1. **As a developer**, I want to see what files changed between two checkpoints so I can understand what I did before a restore.

2. **As a developer**, I want to see the actual content diff of changed files so I can pinpoint specific changes.

3. **As a user managing costs**, I want to identify near-duplicate checkpoints so I can prune them safely.

4. **As a debugger**, I want to compare "working" vs "broken" checkpoints to find what changed.

5. **As a team member**, I want to understand what a colleague changed in their sprite.

---

## Core Features (MVP)

### 1. Checkpoint Selection
- List all checkpoints for a sprite
- Select two checkpoints to compare (A → B)
- Show checkpoint metadata (name, timestamp, size, trigger type)

### 2. Filesystem Diff Summary
- Tree view of changed files/directories
- Status indicators: Added / Modified / Deleted
- File count summary: "23 files changed, 5 added, 2 deleted"
- Size delta: "+2.3 MB" or "-500 KB"

### 3. File Content Diff
- Side-by-side or unified diff view for text files
- Syntax highlighting based on file extension
- Line numbers
- Expand/collapse unchanged sections

### 4. Binary File Handling
- Indicate binary files changed (no content diff)
- Show size change
- For images: side-by-side thumbnail preview (stretch goal)

---

## Extended Features (Post-MVP)

### 5. Directory-Level Comparison
- Drill down into specific directories
- Aggregate stats per directory

### 6. Process/Service Diff
- What services were running in each checkpoint?
- What ports were listening?
- Environment variable changes

### 7. Similarity Score
- "These checkpoints are 98% identical"
- Helps identify pruning candidates

### 8. Export
- Download diff as patch file
- Export summary as JSON/Markdown

### 9. Three-Way Diff
- Compare three checkpoints (e.g., common ancestor)
- Useful for understanding divergent branches

---

## Technical Approach

### How Sprites Checkpoints Work

Based on sprites.dev documentation:
- Checkpoints are transactional snapshots of the entire Sprite environment
- Copy-on-write storage means only changed blocks are stored
- Checkpoints include filesystem, installed packages, running processes

### The Challenge

The Sprites API (as publicly documented) doesn't expose filesystem-level checkpoint data. We need a way to access the contents of a checkpoint to diff it.

### Approach Options

**Option A: Restore-and-Snapshot**
1. Restore sprite to checkpoint A
2. Create filesystem manifest (file list + hashes)
3. Restore sprite to checkpoint B
4. Create filesystem manifest
5. Diff the manifests
6. For changed files, fetch content from each state

*Pros:* Works with current API
*Cons:* Slow, disruptive (requires actual restores), can't diff while sprite is in use

**Option B: Agent-Based**
1. Install a lightweight agent in the sprite
2. Agent creates manifests on checkpoint
3. Manifests stored alongside checkpoints
4. Diff tool compares manifests

*Pros:* Fast, non-disruptive
*Cons:* Requires agent installation, manifests only exist for future checkpoints

**Option C: Sprites API Enhancement**
1. Request Sprites platform add checkpoint filesystem API
2. `GET /sprites/{name}/checkpoints/{id}/files` → file tree
3. `GET /sprites/{name}/checkpoints/{id}/files/{path}` → file content

*Pros:* Clean, fast, non-disruptive
*Cons:* Requires platform changes (not in our control)

**Recommended: Hybrid (B + A fallback)**
- Use agent-based manifests for new checkpoints
- Fall back to restore-and-snapshot for historical checkpoints
- Advocate for Option C with Sprites team

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                     DIFF VIEWER UI                          │
│                   (Web App or TUI)                          │
│                                                             │
│  • Checkpoint selector                                      │
│  • File tree view                                           │
│  • Diff viewer                                              │
│  • Summary stats                                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ HTTP/CLI
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    DIFF SERVICE                             │
│              (Elixir GenServer or CLI)                      │
│                                                             │
│  • Manifest generation                                      │
│  • Manifest comparison                                      │
│  • File content fetching                                    │
│  • Caching                                                  │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
┌───────────────────┐     ┌───────────────────┐
│   SPRITES API     │     │   SPRITE AGENT    │
│                   │     │   (optional)      │
│ • List checkpoints│     │                   │
│ • Restore         │     │ • Create manifest │
│ • Exec commands   │     │ • Serve files     │
└───────────────────┘     └───────────────────┘
```

### Manifest Format

```json
{
  "checkpoint_id": "checkpoint-2025-01-20T12:00:00Z",
  "sprite": "my-sprite",
  "created_at": "2025-01-20T12:00:00Z",
  "files": [
    {
      "path": "/home/user/app/lib/my_app.ex",
      "type": "file",
      "size": 2048,
      "sha256": "abc123...",
      "mtime": "2025-01-20T11:55:00Z",
      "mode": "0644"
    },
    {
      "path": "/home/user/app/lib/my_app",
      "type": "directory",
      "mode": "0755"
    }
  ],
  "total_files": 1247,
  "total_size": 52428800
}
```

### Diff Output Format

```json
{
  "checkpoint_a": "checkpoint-2025-01-19T12:00:00Z",
  "checkpoint_b": "checkpoint-2025-01-20T12:00:00Z",
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
    },
    {
      "path": "/home/user/app/lib/new_module.ex",
      "status": "added",
      "size_after": 512
    }
  ]
}
```

---

## Implementation Plan

### Phase 1: CLI Foundation (Week 1)

**Goal:** Basic CLI tool that can list checkpoints and generate manifests.

**Tasks:**

1. **Project setup**
   ```bash
   mix new sprite_diff --sup
   ```

2. **Sprites API client**
   - Authenticate with SPRITES_TOKEN
   - List sprites: `GET /v1/sprites`
   - List checkpoints: `GET /v1/sprites/{name}/checkpoints`
   - Restore checkpoint: `POST /v1/sprites/{name}/checkpoints/{id}/restore`
   - Execute command: `POST /v1/sprites/{name}/exec`

3. **Manifest generator**
   - SSH or exec into sprite
   - Run `find` + `stat` + `sha256sum` to build manifest
   - Parse output into structured format
   - Handle large filesystems (streaming, pagination)

4. **Basic CLI commands**
   ```bash
   sprite-diff checkpoints my-sprite
   # Lists all checkpoints with metadata
   
   sprite-diff manifest my-sprite checkpoint-abc
   # Generates and displays manifest for a checkpoint
   ```

**Deliverable:** CLI that can list checkpoints and create manifests.

---

### Phase 2: Diff Engine (Week 2)

**Goal:** Compare two manifests and produce diff output.

**Tasks:**

1. **Manifest comparison algorithm**
   - Index files by path
   - Detect added (in B, not in A)
   - Detect deleted (in A, not in B)
   - Detect modified (in both, different hash)
   - Detect renamed (same hash, different path) — stretch goal

2. **Diff summary generation**
   - Count changes by type
   - Calculate size deltas
   - Compute similarity score

3. **File content diff**
   - Fetch file content from both checkpoints
   - Use `:diff` or shell out to `diff`
   - Handle text vs binary detection

4. **CLI diff command**
   ```bash
   sprite-diff diff my-sprite checkpoint-a checkpoint-b
   # Shows summary of changes
   
   sprite-diff diff my-sprite checkpoint-a checkpoint-b --file /path/to/file.ex
   # Shows content diff for specific file
   ```

**Deliverable:** CLI that produces meaningful diffs between checkpoints.

---

### Phase 3: TUI Interface (Week 3)

**Goal:** Interactive terminal UI for browsing diffs.

**Tasks:**

1. **TUI framework setup**
   - Use Ratatui (Rust) or similar
   - Or: Elixir with `owl` or `ratatouille`

2. **Checkpoint selector panel**
   - List checkpoints with timestamps
   - Keyboard navigation
   - Select A and B checkpoints

3. **File tree panel**
   - Expandable directory tree
   - Color-coded status (green=added, yellow=modified, red=deleted)
   - File counts per directory

4. **Diff viewer panel**
   - Syntax-highlighted content diff
   - Scroll through changes
   - Jump to next/previous change

5. **Summary panel**
   - Stats at a glance
   - Similarity score
   - Size delta

**Deliverable:** Interactive TUI for exploring checkpoint diffs.

---

### Phase 4: Agent for Fast Manifests (Week 4)

**Goal:** Optional agent that creates manifests automatically on checkpoint.

**Tasks:**

1. **Agent design**
   - Lightweight daemon running in sprite
   - Watches for checkpoint events (or triggered via API)
   - Generates manifest and stores locally

2. **Manifest storage**
   - Store in `/.sprite-diff/manifests/`
   - Or push to external storage (S3, Gallery sprite, etc.)

3. **Integration with diff tool**
   - Check for cached manifest first
   - Fall back to live generation if not found

4. **Installation script**
   ```bash
   sprite-diff install-agent my-sprite
   # Installs and configures agent in sprite
   ```

**Deliverable:** Fast diffs via pre-computed manifests.

---

### Phase 5: Web UI (Week 5-6)

**Goal:** Browser-based interface for teams and non-CLI users.

**Tasks:**

1. **Phoenix app setup**
   ```bash
   mix phx.new sprite_diff_web --no-ecto
   ```

2. **Authentication**
   - OAuth with Fly.io
   - Or: paste Sprites API token

3. **LiveView UI**
   - Sprite selector dropdown
   - Checkpoint timeline/list
   - Interactive file tree (LiveView component)
   - Diff viewer with syntax highlighting (Monaco or CodeMirror)

4. **Sharing**
   - Generate shareable link to specific diff
   - Useful for team debugging

5. **Deployment**
   - Deploy as Fly.io app
   - Or: deploy as a Sprite (dogfooding!)

**Deliverable:** Web app for checkpoint diffing.

---

## Tech Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| CLI core | Elixir | Matches Sprites ecosystem, good for concurrency |
| HTTP client | Req | Modern, simple Elixir HTTP client |
| TUI | Ratatouille or Owl | Elixir-native terminal UI |
| Web UI | Phoenix LiveView | Real-time updates, Elixir ecosystem |
| Diff algorithm | Custom + `diff` | Fast path detection + content diff |
| Syntax highlighting | Makeup (Elixir) or Prism (JS) | Language-aware highlighting |

---

## Sprites API Requirements

### Currently Available (per sprites.dev docs)
- List sprites
- Create/delete sprites
- List checkpoints
- Create checkpoint
- Restore checkpoint
- Execute commands

### Would Be Helpful (feature requests)
- `GET /sprites/{name}/checkpoints/{id}/manifest` — filesystem manifest without restore
- `GET /sprites/{name}/checkpoints/{id}/file?path=/foo` — file content from checkpoint
- Checkpoint event webhooks — notify when checkpoint created

---

## CLI Command Reference

```bash
# List checkpoints
sprite-diff checkpoints <sprite-name>
sprite-diff checkpoints <sprite-name> --json

# Generate manifest for a checkpoint
sprite-diff manifest <sprite-name> <checkpoint-id>
sprite-diff manifest <sprite-name> <checkpoint-id> --output manifest.json

# Compare two checkpoints
sprite-diff diff <sprite-name> <checkpoint-a> <checkpoint-b>
sprite-diff diff <sprite-name> <checkpoint-a> <checkpoint-b> --summary
sprite-diff diff <sprite-name> <checkpoint-a> <checkpoint-b> --json

# View specific file diff
sprite-diff file <sprite-name> <checkpoint-a> <checkpoint-b> <file-path>

# Interactive TUI
sprite-diff ui <sprite-name>

# Install agent (optional, for fast manifests)
sprite-diff agent install <sprite-name>
sprite-diff agent status <sprite-name>
sprite-diff agent uninstall <sprite-name>

# Compare latest checkpoint to current state
sprite-diff diff <sprite-name> <checkpoint-id> HEAD
```

---

## Example Session

```bash
$ sprite-diff checkpoints my-app

CHECKPOINTS FOR my-app
─────────────────────────────────────────────────────────
 ID                          CREATED              SIZE
─────────────────────────────────────────────────────────
 checkpoint-2025-01-20-pm    2025-01-20 14:30    52.3 MB
 checkpoint-2025-01-20-am    2025-01-20 09:00    51.8 MB
 checkpoint-2025-01-19       2025-01-19 17:00    51.2 MB
 checkpoint-2025-01-18       2025-01-18 12:00    48.0 MB
─────────────────────────────────────────────────────────

$ sprite-diff diff my-app checkpoint-2025-01-19 checkpoint-2025-01-20-pm

COMPARING checkpoint-2025-01-19 → checkpoint-2025-01-20-pm
─────────────────────────────────────────────────────────

SUMMARY
  Files changed:  47
  Files added:    12
  Files deleted:   3
  Size delta:     +1.1 MB
  Similarity:     94.2%

CHANGES
  M  lib/my_app/accounts.ex           +45 -12
  M  lib/my_app/accounts/user.ex      +23 -5
  A  lib/my_app/billing.ex            +156
  A  lib/my_app/billing/invoice.ex    +89
  D  lib/my_app/legacy_auth.ex        -203
  M  config/config.exs                +3 -1
  ... (41 more files)

$ sprite-diff file my-app checkpoint-2025-01-19 checkpoint-2025-01-20-pm lib/my_app/accounts.ex

── lib/my_app/accounts.ex ──────────────────────────────

@@ -15,6 +15,18 @@ defmodule MyApp.Accounts do
   def get_user(id) do
     Repo.get(User, id)
   end
+
+  def get_user_with_billing(id) do
+    User
+    |> where([u], u.id == ^id)
+    |> preload(:invoices)
+    |> Repo.one()
+  end
+
+  def list_active_users do
+    User
+    |> where([u], u.active == true)
+    |> Repo.all()
+  end
 end
```

---

## Success Metrics

- **Adoption:** Number of users/teams using the tool
- **Time saved:** Reduction in "what changed?" debugging time
- **Checkpoint hygiene:** Users pruning unnecessary checkpoints
- **Feature requests:** Demand for web UI, additional features

---

## Open Questions

- [ ] Should this be an official Sprites tool or community/third-party?
- [ ] What's the best way to handle large sprites (10GB+)?
- [ ] Should diffs be cacheable/storable?
- [ ] Integration with CI/CD pipelines?
- [ ] Pricing model if offered as a service?

---

## Milestones

| Milestone | Description | Target |
|-----------|-------------|--------|
| M1 | CLI lists checkpoints | Week 1 |
| M2 | CLI generates manifests | Week 1 |
| M3 | CLI produces diff summary | Week 2 |
| M4 | CLI shows file content diffs | Week 2 |
| M5 | TUI browsable and functional | Week 3 |
| M6 | Agent for fast manifests | Week 4 |
| M7 | Web UI MVP | Week 6 |
| M8 | Public release | Week 7 |
