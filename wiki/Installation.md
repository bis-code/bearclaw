How to install bearclaw, what the installer is mechanically prevented from touching, and how to back out.

## Quick start

```bash
git clone https://github.com/bis-code/bearclaw.git ~/bearclaw
cd ~/bearclaw
./install.sh --dry-run     # see exactly what it will do
./install.sh               # symlink it into ~/.claude
./bin/claude-setup-doctor  # verify
```

Then start a new Claude Code session — hooks and rules are read at session start, so an already-running session won't pick them up.

`--dry-run` prints one `would: …` line per action and changes nothing, including the plugin install and the memory-index build. Read that output before the real run; it is the cheapest way to understand the installer.

## What install.sh actually does

The installer is short and deliberately boring. It symlinks four files and seven directories from the repo into `DEST` (default `~/.claude`):

| Kind | Entries |
|---|---|
| Files | `CLAUDE.md`, `.mcp.json`, `settings.json`, `statusline.sh` |
| Directories | `rules`, `skills`, `hooks`, `agents`, `bin`, `commands`, `memory-global` |

Beyond the symlinks it does five things:

1. **Sets executable bits** on `statusline.sh`, `hooks/*.sh`, `hooks/lib/*.sh`, `scripts/*.sh`, and `bin/*` — targeting the repo directly, since `chmod` follows symlinks. `*.test.sh` files are skipped on purpose: they are invoked as `sh <file>`, never executed directly, so chmod-ing them would dirty the tree against their tracked mode on every install.
2. **Installs the `deep-think` plugin** if the `claude` CLI is on PATH (`claude plugin marketplace add` + `claude plugin install`, both idempotent). Skipped with a printed note when the CLI isn't found.
3. **Seeds `rules/about-me.local.md`** from `rules/about-me.example.md` — only if absent, never overwritten. That file is gitignored; it is where your persona lives.
4. **Initializes the capture store** layout under `$XDG_STATE_HOME/claude-memory` (see [[Memory-System]]).
5. **Builds the semantic memory index** if `leann` is installed; otherwise prints `note: leann not found — semantic memory recall is disabled (everything else works)` and moves on.

Re-running is idempotent: an entry that is already the correct symlink prints `ok <name>` and is left alone. Safe to re-run after `git pull`.

### Installing to a non-default root

`./install.sh [DEST]` takes an explicit destination, which is also how CI exercises it (`./install.sh "$RUNNER_TEMP/claude-real"`). Useful for trying bearclaw against a throwaway root before adopting it.

## The guarantees

From the script's own header: **it touches only `$DEST` and `$XDG_STATE_HOME/claude-memory`.** Specifically it never runs `git config --global`, never writes `~/.gitconfig`, and never appends to your shell rc files.

That is not a promise in prose only — `scripts/tests/install.bats` asserts it, and CI runs an install/uninstall round-trip on every push and pull request (see [[Testing-and-CI]]). If a future change started editing your shell config, the suite would fail.

## Backups of pre-existing files

Anything already at a target path — real file, real directory, or a foreign symlink — is **moved**, not deleted, into `$DEST/backups/pre-install-<YYYYmmdd-HHMMSS>/` before the symlink is created. The installer prints `backups saved to: <path>` at the end when it created one. Each run gets its own timestamped directory, so a second install never overwrites the first backup.

`backups/` is gitignored, so restoring is a plain `mv` back.

## Uninstall

```bash
~/bearclaw/install.sh --uninstall
```

It removes **only symlinks it created**, verified per entry: the path must be a symlink *and* its `readlink` target must point back into this repo. A real file or a foreign symlink prints `skip <name> (not our symlink)` and is left in place. Your memory under `~/.claude` and `~/.local/state/claude-memory` is not touched — the script says so on exit.

To fully revert, uninstall and then restore whatever you want from the newest `backups/pre-install-*` directory.

## Doctor

```bash
~/.claude/bin/claude-setup-doctor
# or
~/bearclaw/bin/claude-setup-doctor
```

Seven check groups: symlink integrity, hook script executable bits, JSON validity, settings cascade, MCP commands resolvable, repo git state, marketplace reachability. Each check reports `PASS` / `WARN` / `FAIL`; the exit code is non-zero only on `FAIL`, so it is safe to run in a loop or a login script. It resolves its own physical location with `cd -P`, so invoking it through the `~/.claude/bin` symlink still finds the real repo root.

Run it after every `git pull` and any time a session behaves as though a hook vanished.

## Dependencies

**Required:** `jq`. Hooks and scripts parse their stdin payloads with it. Most hooks fail open without it, meaning they no-op rather than break your session — but install `jq` first and you avoid a class of confusing silence.

**Optional**, with the exact degradation:

| Tool | Enables | If absent |
|---|---|---|
| `gh` | the `roadmap` skill, PR/issue-aware workflows | Those skills degrade to asking you to run `gh` manually. |
| `leann` | semantic memory recall (`userpromptsubmit-memory-recall.sh`, `stop-memory-index-rebuild.sh`) | Memory still works as plain file reads — no similarity search. `install.sh` prints a note and skips index building. |
| `deep-think@bis-code` (Claude Code plugin) | architecture/design nudges (`userpromptsubmit-deepthink-nudge.sh`) | The hook degrades silently — it checks the installed-plugins file first and stays quiet rather than nudging toward a tool that cannot start. `install.sh` installs the plugin automatically when the `claude` CLI is on PATH. |
| `bats`, `shellcheck` | running the test suite and pre-push lint locally | CI still runs them; `scripts/test-all.sh` prints `skip (bats not installed)` for the bats lane. |
| `terminal-notifier` (macOS) | branded desktop attention notifications | `notify-attention.sh` falls back to plain `osascript`, then to a silent no-op on non-macOS. |

## Permissions

bearclaw ships `defaultMode: "acceptEdits"` — Claude edits files freely but asks before running commands. That is deliberate.

If you want `bypassPermissions`, set it yourself in `~/.claude/settings.local.json`, which overrides the repo's `settings.json` and is never committed:

```json
{ "permissions": { "defaultMode": "bypassPermissions" } }
```

Read the background-agent safety rule in [[Rules]] first. It documents a real data-loss incident caused by exactly that mode combined with a background agent lacking isolation. `hooks/guard-destructive.py` is the backstop and blocks catastrophic deletes regardless of permission mode — but it is a denylist, not a guarantee.

## Tunable settings

Set these in `settings.json` (tracked) or `settings.local.json` (yours, untracked):

| Key | Default | Purpose |
|---|---|---|
| `autoCompactWindow` | `500000` (set in `settings.json`) | Token threshold that triggers auto-compact. |
| `handoffReminderStartPct` | `60` (hook fallback — not set in `settings.json`) | First handoff warning fires at this percentage of `autoCompactWindow`. |
| `handoffReminderBandPct` | `10` (hook fallback — not set in `settings.json`) | Each subsequent re-warning needs another N% on top of the prior one. |
| `effortLevel` | `auto` | Reasoning depth. `auto` lets the harness scale per call and stops sub-agent fan-outs from each spawning at high effort — the main quota lever. |
| `memorySlimLoad` | `true` | Skips the eager SessionStart memory dump because the recall hook serves entry bodies on demand. |
| `CLAUDE_PROJECT_ROOTS` (env) | `$HOME` | Space-separated roots the audit tooling scans. |

## Mirroring to a second config root

If you run more than one `CLAUDE_CONFIG_DIR` — a second account, or a separate machine profile — `bin/claude-mirror-tooling` gives both roots the same tooling without merging their identities:

```bash
claude-mirror-tooling ~/.claude ~/.claude-other
```

It mirrors only tooling **directories** (`rules`, `hooks`, `agents`, `bin`, `commands`, `skills`) and never touches files — `settings.json`, `.mcp.json`, `CLAUDE.md`, `statusline.sh`, auth and runtime state stay per-root, so each root keeps its own subscription and its own MCP set. Directory symlinks are created only if absent; an existing real directory or foreign symlink is left untouched, so nothing is clobbered. `skills` is handled additively: each source skill is linked in only when missing, preserving skills that belong to that other root alone.

Global memory is deliberately **not** shared. `seed_memory_global()` seeds an empty, unshared `memory-global/` in the destination instead of symlinking it, so one root's cross-cutting memory never leaks into the other's context. Re-run the command after adding skills or agents to propagate them; behavior is covered by `bin/claude-mirror-tooling.test.sh`.

## Pre-push lint

`scripts/pre-push.sh` is the repo's own pre-push guard. Wire it up with a symlink from the checkout:

```bash
ln -s ../../scripts/pre-push.sh ~/bearclaw/.git/hooks/pre-push
```

Details of what it runs are in [[Testing-and-CI]].
