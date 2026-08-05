A three-tier memory system that fills up as you work, behind a review gate you control — and never leaves your machine.

## The three tiers

| Tier | Location | Committed | Loaded | Holds |
|---|---|---|---|---|
| Rules | `rules/*.md` | yes | every session | Behavioral instructions — see [[Rules]]. |
| Global memory | `memory-global/` → `~/.claude/memory-global/` | scaffolding only; your entries are gitignored | every session, via the SessionStart hook | Cross-cutting facts and failures that hold regardless of which project you're in. |
| Repo-local memory | `<repo>/.claude/memory/` | gitignored by default | when the session's directory is that repo | Project-specific facts and failures for that one project. |

**The classification rule:** *global* if it's true regardless of which repo you're in — CLI and tool behavior, cross-project conventions, your preferences, reusable failure fixes. *Repo-local* if it only means something for one project — its decisions, layout, quirks, errors. When unsure, choose repo-local: promoting later is cheaper than over-globalizing.

`memory-global/` ships **empty** apart from three scaffolding files (`README.md`, `MEMORY.md`, `ERRORS.md`). It fills as you work.

An older location, `~/.claude/projects/<cwd>/memory/`, is deprecated. Entries there still load natively and migrate lazily when next touched; `hooks/lib/memory-migrate.sh` (exposed as `claude-memory-migrate`) onboards the current project explicitly — it resolves the main worktree so a linked worktree onboards its parent repo rather than itself, copies any legacy entries not already present (purely additive, existing entries are never overwritten, legacy is never deleted), and rebuilds the project's index.

## The loop

Memory in bearclaw is a three-stage loop, and the split between the stages is forced by one hard constraint: **a shell hook cannot call an LLM.** So hooks stage raw signal cheaply, and Claude does the thinking later, when it's active anyway.

### 1. Capture (hooks, no LLM)

`sessionend-memory-capture.sh` runs on both `SessionEnd` and `PreCompact` and writes a **raw capture pointer** — a small JSON record naming the session, its transcript path, the resolved project, and its signal file — into `~/.local/state/claude-memory/_pending/raw/`. Not distilled memory: a pointer. This is what makes sessions that ended without a `/handoff` recoverable, and wiring the same script to `PreCompact` means compaction doesn't lose the pointer either.

Alongside it, `stop-memory-signal.sh` runs on every turn end as a **heuristic, no-LLM high-signal detector**: it regexes the last user and assistant exchange and appends a marker (`{ts, kind, snippet}` where kind is `resolved`, `praise`, or `correction`) to a per-session signal file. That gives the setup between-prompt awareness without between-prompt LLM cost. One filter in it is load-bearing: tool results are recorded with `role=="user"` — that's the harness talking, not you — and before they were filtered out, CLI stderr was being banked as a user correction.

The on-disk layout under `~/.local/state/claude-memory/` is defined by `hooks/lib/memory-store.sh`: `_pending/raw/` for pointers awaiting distillation, `_pending/signals/` for per-session markers, `_pending/done/` as an age-bounded audit trail of drained captures, and `_usage/` for the recall log that feeds scoring.

### 2. Review gate (the memory-capture skill)

Nothing reaches live memory without your explicit accept. The next SessionStart surfaces a "Memory review queue" nudge; the `memory-capture` skill drains it. Two entry paths, one shared middle:

| Path | When | Gate |
|---|---|---|
| Interactive | invoked from `/handoff`, session still fresh in context | `AskUserQuestion` now; accepted candidates written to repo-local memory directly |
| Deferred drain | the SessionStart nudge, or "drain the memory queue" | each pointer read oldest-first, distilled from its transcript, asked, accepted entries written, pointer marked done |

Both run **distill → dedup → ask → write**:

- **Prioritize** the turns flagged in the signal file first. They are the dilution-resistant core — an error that got resolved, an explicit correction, a "that worked" — and distilling them first fixes candidate dilution in long sessions.
- **Distill** into 0–N candidates, each exactly one fact: a reusable failure→fix, or a design decision or convention. Concrete and reusable, not "we discussed X", and dated with a "verified YYYY-MM-DD" line. **Zero candidates is a valid outcome** — if nothing clears the bar, the skill says so and stops.
- **Dedup** each candidate against the index via `hooks/lib/memory-dedup.sh`, which prints a similarity score plus `SKIP` or `NEW`. It compares word-token Jaccard overlap rather than raw index scores, because raw scores are unnormalized dot products that aren't threshold-stable across text lengths, while Jaccard is scale-invariant. Default threshold 0.6.
- **Ask, then write.** Classification defaults to repo-local; promotion to global is a separate deliberate step.

### 3. Recall (hook + optional semantic index)

`userpromptsubmit-memory-recall.sh` injects relevant entries into context per prompt, rather than dumping everything at session start. It skips trivial prompts — fewer than four words, `y`/`yes`/`no`/`ok`/`continue`, anything starting with `/` — then searches two indexes: the global one, named after the active config root, and the current repo's, resolved from the **main** worktree so all linked worktrees share one index. Results merge and pass through `hooks/lib/memory-recall.py` with a relevance floor, a top-k of 3, and a 400-token budget, and the block comes back as `additionalContext`.

Which entries were surfaced is appended to `_usage/recall-log.jsonl`, and that log feeds frequency and recency scoring on later turns — memory that keeps proving useful surfaces more readily. The same log powers `hooks/lib/memory-prune.sh`, which flags entries not recalled within a window (90 days by default) as a **review list and never deletes anything**; pruning stays a deliberate manual step.

The semantic index itself is optional. With `leann` installed, `hooks/lib/memory-index-build.sh` stages a recall corpus (curated per-file entries, plus `ERRORS.md` split into one file per entry so a single error is retrievable on its own) and builds the index. `stop-memory-index-rebuild.sh` rebuilds it when a memory file changed, gated on mtime so it's nearly free when nothing did, and running in the background so it never delays a turn. Without `leann`, memory still works as plain file reads — you just lose similarity search.

`scripts/memory-doctor.sh` validates one tier's index and `ERRORS.md` cap. Report mode is read-only; `--apply` makes only safe fixes (removing dangling index lines, appending review-marked stubs for orphan entry files) and never deletes an entry file, rotates `ERRORS.md`, or prunes notes.

## Conventions

### MEMORY.md is an index, not content

`MEMORY.md` holds one line per entry: `- [Title](slug.md) — one-line hook (~150 chars).` Never write content into it. The index is loaded into every session and long entries truncate; the body belongs in the linked file.

Each entry file is one fact, with frontmatter carrying `name`, `description`, and `metadata.type`.

### One entry, one fact

Don't bundle "X is true" plus "Y is true" plus "the reason for Y" into a single entry — those three claims age at different rates, and a bundled entry goes stale as a unit. Date the verification in the body when you bank it, so future-you can judge currency. Link related entries with `[[name]]`: memory becomes a graph, and isolated entries decay faster than connected ones.

### Verify before citing

The core operating rule: **before citing any structural claim from memory, verify it.** Entries that survive cycles of change read as fact long after the underlying state shifted, and they survive context compactions intact. Structural claims include file paths, invariants, topology ("symlinked from", "auto-built by"), active processes, deployment state, pipeline ownership, and workflow status.

Verification is one cheap call: `ls` a path, `readlink` a symlink, `git log -1 --oneline` a branch, `gh api` for GitHub state, `grep` for a content claim, `docker inspect` for runtime state. Two checkpoints where it pays: a structural sanity sweep at session start (especially after a compact or a handoff resume — roughly 30 seconds for the load-bearing claim in each section), and before any teammate dispatch or large irreversible action whose brief cites a memory.

**Remove on contradiction.** If today's reality contradicts an entry and you confirm reality is right, delete or rewrite the entry. Don't leave it standing with a footnote.

The anti-patterns, stated plainly: "MEMORY says X, therefore X is true"; adding a note next to a wrong entry instead of fixing it; citing a memory in a brief without checking the citation still holds; and banking the same lesson twice under different names — search first, update if it exists.

## ERRORS.md

A failure journal that sits alongside `MEMORY.md` in the same tier and follows the same committed/ignored policy. It answers a different question: *"I've hit this before, what fixed it?"*

Entry format, newest first:

```
## [YYYY-MM-DD] <symptom> — <one-line resolution>
- **Trigger:** the command/condition that produced it (the searchable symptom)
- **Cause:** root cause, one line
- **Fix:** the exact command/flag/change that resolved it
- **Scope:** repo/tool/env it applies to (so it's prunable when that dies)
```

**Append only when all three hold:** you had to look it up or ask, so it cost real time; it's environment- or tooling-specific rather than an in-flux code-logic bug; and the fix is concrete and reusable.

**Do not log** transient bugs in your own diff, anything already in `MEMORY.md`, or "we discussed X" — that's a decision, and decisions go to `MEMORY.md`.

**Prune** at a 200-line cap by rotating the oldest resolved entries into `ERRORS.archive.md` in the same tier's directory, which inherits that tier's committed status. Never silently truncate. Delete entries outright on scope-death, when the repo or tool named in `Scope:` is gone.

### Which file?

> *"Would I grep this when something breaks?"* → `ERRORS.md`.
> *"Would I cite this when designing?"* → `MEMORY.md`.

`templates/ERRORS.md.seed` is the starting file.

## The privacy guarantee

**Nothing you write into memory leaves your machine.**

Mechanically: `.gitignore` excludes `memory-global/*.md` with explicit exceptions for only the three scaffolding files, so every entry you actually record is untracked. Repo-local memory (`/.claude/memory/`) and the capture staging directories (`_pending/`, `_usage/`) are gitignored too. If you *want* to version your own memory in your own fork, the `.gitignore` says which two lines to delete.

Behaviorally: hooks never make network calls or LLM calls — they stage pointers and markers on local disk. Distillation happens inside your own session, and nothing reaches live memory without your explicit accept. The optional semantic index is built by a local tool over local files.

## Related

Hook-level detail for every script named here is in [[Hooks]]. The `memory-capture` skill's triggers and outputs are in [[Skills]]. The memory-hygiene rule that codifies these conventions is summarized in [[Rules]].
