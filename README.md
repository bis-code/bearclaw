# bearclaw

[![ci](https://github.com/bis-code/bearclaw/actions/workflows/ci.yml/badge.svg)](https://github.com/bis-code/bearclaw/actions/workflows/ci.yml)

![bearclaw](docs/banner.jpg)

*Bear from Obsession; Claw from Captain Claw, the game that took most of my
childhood.*

A complete user-scope [Claude Code](https://claude.com/claude-code) config:
16 subagents, 17 skills, 20 hook scripts (19 wired as lifecycle hooks), a
three-tier memory system that grows as you work, and a safety guard that
blocks catastrophic deletes regardless of permission mode.

Deeper documentation lives in the [wiki](https://github.com/bis-code/bearclaw/wiki)
— per-hook rationale, the full skill/agent catalogs, the memory loop, and the
testing/identity-gate story.

The repo *is* the config. `install.sh` symlinks it into `~/.claude/`, so
editing the live config edits the repo and your changes stay version
controlled. Commit drift yourself; `bin/claude-setup-doctor` warns when the
tree is dirty.

## Install

```bash
git clone https://github.com/bis-code/bearclaw.git ~/bearclaw
cd ~/bearclaw
./install.sh --dry-run     # see exactly what it will do
./install.sh               # symlink it into ~/.claude
./bin/claude-setup-doctor  # verify
```

Existing files in `~/.claude/` are backed up to `~/.claude/backups/pre-install-*`.
Re-running is idempotent. `./install.sh --uninstall` removes only the symlinks
it created and never touches your memory. **`install.sh` touches only its
`DEST` (default `~/.claude`) and your memory-index state dir — it never runs
`git config --global`, never writes `~/.gitconfig`, and never appends to your
shell rc files.** That's mechanically enforced by
`scripts/tests/install.bats`, not just a claim.

**Required:** `jq`, `git`, `python3` (the catastrophic-delete guard is a
python3 hook). **Optional:** `gh` (roadmap/PR skills), `leann` (semantic
memory recall), the `deep-think@bis-code` Claude Code plugin (architecture/design
nudges), `bats` + `shellcheck` (running the test suite yourself). `install.sh`
runs a preflight first: it aborts with install hints if a required tool is
missing and prints a note per absent optional one, so a skipped feature is a
visible choice — it checks only, and never installs software itself. See
[Optional dependencies](#optional-dependencies) for exactly what degrades.

## Layout

```
CLAUDE.md           # user-scope context, loaded every session
.mcp.json           # MCP servers (deep-think now ships as the deep-think@bis-code plugin; hooks degrade if absent)
settings.json       # 11 configured plugins (9 enabled by default), 19 wired hooks, effortLevel, autoCompactWindow
statusline.sh       # status line (model · cwd · branch · token meters)
rules/              # canonical rules — behavioral instructions, loaded every session
skills/             # 16 skills (handoff, handoff-autonomously, goal-prompt, walkthrough, ...)
agents/             # 16 named subagents (reviewers, implementers, planners)
hooks/              # 18 hook scripts (see "Hooks" below) + hooks/lib/ (memory subsystem)
memory-global/      # global memory tier: MEMORY.md index + ERRORS.md + one fact per file
bin/                # operational scripts (claude-setup-doctor, cost report, review markers, ...)
commands/           # slash commands (/cost-report)
scripts/            # pre-push lint, test-all.sh, check-no-identity.sh, and scripts/tests/
templates/          # seed files (ERRORS.md.seed)
install.sh          # symlinks repo → ~/.claude/, idempotent
```

## What you get

### Agents (`agents/`, 16)

Read-only reviewers, implementers, and planners, dispatched via the `Agent`
tool.

| Group | Agents |
|---|---|
| Reviewers (read-only) | `architect-reviewer`, `code-reviewer`, `security-reviewer`, `performance-reviewer` |
| Language reviewers (read-only, on-demand) | `go-reviewer`, `swift-reviewer`, `typescript-reviewer`, `java-reviewer`, `csharp-reviewer`, `python-reviewer` |
| Implementers | `tdd-guide`, `refactor-cleaner`, `doc-updater` |
| Planners / debuggers | `planner`, `incident-debugger`, `build-error-resolver` |

Each language reviewer detects the project's stack (e.g. `java` → Spring vs
Quarkus vs Vert.x) and applies general-language rules always, stack-specific
checks only when it detects that stack.

### Skills (`skills/`, 16)

`address-review-comments`, `agent-self-evaluation`, `context-budget`,
`contract-audit`, `editing-pr-descriptions`, `find-skills`, `goal-prompt`,
`handoff`, `handoff-autonomously`, `monthly-setup-audit`,
`roadmap`, `swift-actor-persistence`, `swift-concurrency-6-2`,
`swift-protocol-di-testing`, `visual-companion`, `walkthrough`.

`walkthrough` turns any item-list or long report into an interactive deck —
one AskUserQuestion card per item, a decision log + tracker sync at the end,
and a queue-instead-of-stall mode under an active `/goal`.

`handoff` is the core session-continuity skill (writing a durable lesson
directly into repo-local `.claude/memory/` is a manual step described there —
no capture skill or auto-trigger does it for you); `monthly-setup-audit` is a
read-only health check of this setup itself. `handoff-autonomously` = `handoff`
+ a `/goal` line (built by `goal-prompt`, which embeds the official `/goal`
docs — models don't know the command natively) so the next session after
`/clear` can run unattended.

### Hooks (`hooks/`, 18 scripts)

17 are wired into `settings.json` as lifecycle hooks; `memory-index-freshness.sh`
is a shared library called by `install.sh` and `stop-memory-index-rebuild.sh`
rather than registered directly.

| Event | Script | What it does |
|---|---|---|
| `SessionStart` | `sessionstart-load-memory.sh` | Surfaces memory regardless of cwd — loads the global index plus any repo-local memory for the current project. |
| `SessionStart` | `sessionstart-heal-settings.sh` | Repairs `settings.json` when a Claude Code atomic-write (on `/config`, `/effort`, plugin changes) replaces the repo symlink with a real file and drops repo-only keys. |
| `PreToolUse` (`Bash`) | `pretooluse-confirm-gate.sh` | Denies outward-facing / hard-to-reverse Bash commands unless prefixed `CLAUDE_CONFIRMED=1`. Holds even under permission-bypass modes. |
| `PreToolUse` (`Bash`) | `pretooluse-secret-guard.sh` | Advisory only (never blocks) — warns when a command would dump secret-bearing file contents into the transcript. |
| `PreToolUse` (`Bash`) | `guard-destructive.py` | Blocks catastrophic destructive shell commands (`rm -rf ~`, `git clean -fdx`, recursive `chmod`/`chown` over home, …) regardless of permission mode. See `scripts/tests/guard-destructive.bats`. |
| `PreToolUse` (`Edit\|Write\|MultiEdit`) | `pretooluse-config-protection.sh` | Confirms before modifying an *existing* lint/format config, to block "weaken the linter to silence the error." New configs pass freely. |
| `PreToolUse` (`Task\|Agent`) | `pretooluse-dispatch-gate.sh` | Steers a general-purpose dispatch toward a named agent when the prompt clearly matches one — denies once per session, not a hard wall. |
| `PreToolUse` (`Skill`) | `pretooluse-verification-pair.sh` | Enforces that a verification skill runs before a "finish the branch" skill. |
| `UserPromptSubmit` | `userpromptsubmit-deepthink-nudge.sh` | Nudges toward the deep-think plugin's think tool when the prompt matches an architecture/design trigger. Fires at most once per session. |
| `UserPromptSubmit` | `userpromptsubmit-memory-recall.sh` | Injects relevant memory entries into context, gated by relevance. |
| `Notification` | `notify-attention.sh` | Desktop notification, fired only when Claude genuinely needs you, labeled by notification type. |
| `Stop` | `stop-handoff-reminder.sh` | Warns via `systemMessage` once the transcript passes a configurable % of `autoCompactWindow`, so you can run `/handoff` before auto-compact strips context. |
| `Stop` | `stop-askquestion-nudge.sh` | Blocks once per session when a turn ends with a 2-4 way choice written as prose instead of the `AskUserQuestion` tool. |
| `Stop` | `cost-tracker.sh` | Appends a per-turn delta cost row to a local metrics file (non-blocking background write). Backs `/cost-report`. |
| `Stop` | `stop-memory-index-rebuild.sh` | Rebuilds the semantic memory index if a memory file changed since the last build (mtime-gated, cheap when nothing changed). |
| `PreCompact` | `precompact-snapshot.sh` | Writes a git-shaped snapshot (branch, SHA, status, last commits) to `~/.claude/handoffs/` right before compaction discards the conversation. |
| `PostCompact` | `postcompact-resume.sh` | After an **auto**-compact only, injects an instruction to resume the in-flight task from the precompact snapshot. |

## Permissions

This setup ships with `defaultMode: "acceptEdits"` — Claude edits files freely
but asks before running commands. That is deliberate.

If you want `bypassPermissions`, set it yourself in `~/.claude/settings.local.json`
(which overrides this repo's `settings.json` and is never committed):

```json
{ "permissions": { "defaultMode": "bypassPermissions" } }
```

Read `rules/background-agent-safety.md` first. It documents a real incident
where that mode, combined with a background agent lacking worktree isolation,
destroyed a projects tree. `hooks/guard-destructive.py` is the backstop — it
blocks catastrophic deletes **regardless of permission mode** — but it is a
denylist, not a guarantee.

## Memory

Three tiers, described in `rules/memory-hygiene.md`:

| Tier | Location | Committed | Scope |
|---|---|---|---|
| Rules | `rules/*.md` | yes | Behavioral instructions, loaded every session. |
| Global memory | `memory-global/` | scaffolding only — your entries aren't | Cross-cutting facts/failures that apply regardless of which project you're in. |
| Repo-local memory | `<repo>/.claude/memory/` | no (gitignored) | Project-specific facts/failures for that one project. |

Nothing you write into memory leaves your machine — `memory-global/*.md` is
gitignored except the scaffolding files (`README.md`, `MEMORY.md`,
`ERRORS.md`); everything you actually record stays local unless you choose
to version it in your own fork (see the comment in `.gitignore`).

## Optional dependencies

| Tool | Enables | If absent |
|---|---|---|
| `jq` | JSON parsing throughout hooks and scripts | Required — most hooks fail open, but install this one first. |
| `gh` | `roadmap` skill, PR/issue-aware workflows | Those skills degrade to "ask the user to run gh manually." |
| `leann` | Semantic memory recall (`userpromptsubmit-memory-recall.sh`, `stop-memory-index-rebuild.sh`) | Memory still works as plain file reads — just no similarity search. `install.sh` prints a note and skips index building. |
| `fastembed` (in a venv `install.sh` sets up, guarded on `python3`) | The `local-embed` memory backend — a lighter, no-service alternative to `leann` (`hooks/lib/local-embed.py`) | `memoryBackend` stays `none` (plain file reads); set it to `local-embed` in `settings.json` once the venv is usable to opt in. |
| `deep-think@bis-code` (Claude Code plugin) | Architecture/design nudges (`userpromptsubmit-deepthink-nudge.sh`) | Hook degrades silently; you reason without the nudge. `install.sh` installs the plugin automatically if the `claude` CLI is on PATH. |
| `ponytail@ponytail` (Claude Code plugin) | Enabled by default in `settings.json`, but its marketplace source is machine-local (like any third-party marketplace) so a fresh checkout won't have it installed yet: `claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail -y` | Claude Code ignores an enabled plugin it can't resolve; nothing breaks, you just don't get ponytail's nudges until installed. |
| `bats`, `shellcheck` | Running the test suite / pre-push lint yourself | CI still runs them; you just can't run `scripts/test-all.sh` locally without `bats`. |

## Doctor

```bash
~/.claude/bin/claude-setup-doctor
# or
~/bearclaw/bin/claude-setup-doctor
```

Seven checks: symlink integrity, hook script executable bits, JSON validity,
settings cascade, MCP commands resolvable, repo git state, marketplace
reachability. Exits non-zero only on FAIL.

## Mirroring to a second config root

`bin/claude-mirror-tooling <src-config-root> <dst-config-root>` mirrors shared
tooling (`rules`, `hooks`, `agents`, `bin`, `commands`, `skills`) from one
`CLAUDE_CONFIG_DIR` into another via symlinks, without touching either root's
account files (`settings.json`, `.mcp.json`, `CLAUDE.md`, auth). Useful if you
run more than one Claude Code config root (e.g. a second account or machine
profile) and want both to see the same tooling. Each root keeps its own
global memory tier — `seed_memory_global()` seeds an empty, unshared
`memory-global/` in the destination rather than symlinking it. Re-run after
adding skills/agents to propagate; see `bin/claude-mirror-tooling.test.sh`.

## Pre-push lint

`install.sh` symlinks `scripts/pre-push.sh` into `.git/hooks/pre-push` (won't
clobber an existing hook). On push, it:

- runs `jq empty` over every tracked `*.json` (except `plugins/`)
- runs `bash -n` over every tracked `*.sh`
- runs `shellcheck -S warning` as advisory (never blocks)
- runs `scripts/test-all.sh`, the aggregate runner over every shell, bats, and
  Python test suite — blocks the push on any failure

Bypass with `git push --no-verify` if you've made a deliberate choice.

## Tunable settings

| Key (in `settings.json` or `settings.local.json`) | Default | Purpose |
|---|---|---|
| `autoCompactWindow` | `500000` (set in `settings.json`) | Token threshold that triggers auto-compact. |
| `handoffReminderStartPct` | `60` (hook fallback — not set in `settings.json`) | First warning fires at this % of `autoCompactWindow`. |
| `handoffReminderBandPct` | `10` (hook fallback — not set in `settings.json`) | Each subsequent re-warning needs +N% on top of the prior. |
| `effortLevel` | `auto` | Reasoning depth. `auto` lets the harness scale per call — the main weekly-quota lever. |
| `CLAUDE_PROJECT_ROOTS` (env) | `$HOME` | Space-separated roots the audit tooling scans. |

## Uninstall

```bash
~/bearclaw/install.sh --uninstall
```

Removes only the symlinks this script created (verified by checking each one
actually points back into the repo before unlinking it — a real file or a
foreign symlink is left alone). Your memory under `~/.claude` and
`~/.local/state/claude-memory` is not touched.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `./scripts/test-all.sh` must be green
before you push — it's the same aggregate runner CI uses, including the
identity-leak gate.

## Philosophy

Anti-bloat. Mirror the live setup, not "what we might want." If a hook,
agent, skill, or rule isn't load-bearing for everyday use, it's out. Re-add
when actually needed.

## License

[MIT](LICENSE)
