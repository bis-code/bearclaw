---
name: memory-capture
description: Use when distilling a finished or paused session into durable memory — either interactively at /handoff time, or draining the SessionEnd/PreCompact raw-capture queue surfaced by the SessionStart "Memory review queue" nudge. Distills candidate lessons, dedups each against the leann index, and writes only what you explicitly accept into repo-local memory. Triggers include "capture this lesson", "bank what we learned", "drain the memory review queue", or the SessionStart review nudge.
---

# Memory Capture

## Overview

Turn session experience into durable memory **behind a review gate**. Shell hooks
cannot call an LLM — they only stage raw signal. This skill is where Claude (active)
does the distillation the hooks cannot: read the raw capture, distill candidate
lessons, dedup, and write only what the user accepts.

**Announce at start:** "I'm using the memory-capture skill to distill and stage memory."

**Core principle — stage → review → accept:** nothing reaches live memory
(`<repo>/.claude/memory/*.md`) without an explicit human accept. Classification
defaults to **repo-local**; promotion to global is a separate deliberate step.

## Two entry paths

| Path | When | Gate |
|---|---|---|
| **Interactive** | invoked from `/handoff` (session fresh in context) | AskUserQuestion *now*; accepted → repo-local memory directly |
| **Deferred drain** | SessionStart "Memory review queue" nudge, or "drain the memory queue" | read each `_pending/raw/` pointer → distill from its transcript → AskUserQuestion → accepted written, pointer marked done |

Both paths run the SAME middle: DISTILL → DEDUP → ASK → WRITE.

## Procedure

### 1. Gather candidates

**Interactive (handoff):** reflect on *this* session's transcript directly.

**Deferred drain:** list the queue and process pointers oldest-first.

```sh
. "$HOME/.claude/hooks/lib/memory-store.sh"
memstore_list_raw     # one raw-capture pointer path per line
```

For each pointer JSON, read `transcript_path` (the session to distill) and
`signal_file` (`_pending/signals/<session>.jsonl`).

### 2. Prioritise high-signal turns

If a `signal_file` exists, read its JSONL markers first
(`{ts,kind,snippet}`, kind ∈ `resolved|praise|correction`). **Distill those turns
first** — they are the dilution-resistant core (an error that got resolved, an
explicit correction, a "that worked"). Then scan the rest of the transcript for
anything else durable. This fixes candidate dilution in long sessions.

### 3. Distill (this is the LLM step — only Claude does it)

Produce 0–N candidate lessons. Each candidate is ONE fact (memory-hygiene:
one entry, one fact). Good candidate shape:

- A reusable failure→fix (→ `ERRORS.md` shape) OR a design decision/convention (→ `MEMORY.md` body).
- Concrete and reusable, not "we discussed X".
- Dated: include "verified YYYY-MM-DD" in the body.

If nothing clears the bar, say so and stop — zero candidates is a valid outcome.

### 4. Dedup each candidate

For every candidate, check it against BOTH tiers it could belong to. Default
tier is repo-local; only consider global if the lesson is true regardless of repo.

```sh
# repo-local index name = "<main-worktree-basename>-memory"
"$HOME/.claude/hooks/lib/memory-dedup.sh" "<repo>-memory" "<candidate text>"
# -> "<max-score> SKIP" or "<max-score> NEW"
```

- `SKIP` (≥ 0.85): a near-duplicate already exists. Do NOT add a second entry.
  Instead, if the existing entry is stale, **bump its `verified:` date** in place
  (memory-hygiene: update in place, don't annotate). Note the skip to the user.
- `NEW`: it's novel — carry it to the gate.

### 5. Gate — AskUserQuestion (keep / edit / drop)

Present surviving candidates via **AskUserQuestion**, one card per candidate, options:
**Keep** · **Edit** · **Drop**. (Conversation Pacing: a small batch is fine here since
each card is independent; do NOT bundle into prose.) For **Edit**, take the user's
revision and re-run dedup (step 4) on the edited text before writing.

NEVER auto-accept. If the user is absent (non-interactive), STOP and leave the raw
pointer in the queue — do not write.

### 6. Write accepted entries (repo-local)

Resolve the main worktree (memory lives there, not a linked worktree):

```sh
GIT_COMMON=$(git -C "<cwd>" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
MAIN_ROOT=$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || echo "<cwd>")
MEM_DIR="$MAIN_ROOT/.claude/memory"
mkdir -p "$MEM_DIR"
```

For each accepted candidate:

1. Write `$MEM_DIR/<slug>.md` with frontmatter matching the memory-hygiene
   convention:

   ```markdown
   ---
   name: <short-kebab-case-slug>
   description: <one-line summary used for recall relevance>
   metadata:
     type: user | feedback | project | reference
   # pinned: true        # only if the user says it's high-value (recall ×1.5)
   # recall_verify: true  # only for high-staleness claims (deploy state, topology)
   ---
   <one-fact body, with "verified YYYY-MM-DD" inline>
   ```

   For `feedback` and `project` type entries, lead the body with:

   ```markdown
   **Why:** <reason this convention exists>

   **How to apply:** <concrete guidance for future application>
   ```

2. Append ONE index line to `$MEM_DIR/MEMORY.md` (create with an `# MEMORY` header
   if absent): `- [<Title>](<slug>.md) — <~150-char hook>`.

**Do NOT commit.** Repo-local memory is gitignored and machine-local; the user
manages persistence. Do NOT write to the global tier — global promotion is a
separate explicit request.

### 7. Close out the queue (deferred drain only)

After processing a pointer (whether or not anything was written), mark it done so
the SessionStart nudge count drops:

```sh
. "$HOME/.claude/hooks/lib/memory-store.sh"
memstore_mark_done "<raw-pointer-path>"
```

## What this skill does NOT do

- **No live write without accept.** AskUserQuestion is mandatory.
- **No global writes by default.** Repo-local is the default tier.
- **No commits.** Captured memory is machine-local.
- **No shell-hook distillation.** Hooks stage raw; this skill (Claude) distills.
- **No second entry for a near-dup.** SKIP → bump verified-date in place instead.

## Dry-run walkthrough (documented; substitutes for a unit test)

Deferred-drain example, end to end:

1. Two sessions ended without a handoff → `_pending/raw/` holds 2 pointers; the
   SessionStart nudge says "2 raw session-capture(s) await review."
2. Invoke memory-capture (deferred). `memstore_list_raw` prints both pointers.
3. Pointer #1's `signal_file` has one `resolved` marker:
   "fixed the word-split by using the `${VAR+x}` seam." Distill →
   candidate: *"Shell test seams: use `if [ -n "${VAR+x}" ]` not
   `${VAR:-default with spaces}` (word-splits). verified 2026-06-18."*
4. `memory-dedup.sh claude-setup-memory "<candidate>"` → `0.41 NEW`.
5. AskUserQuestion → user picks **Keep**.
6. Write `claude-setup/.claude/memory/shell-test-seam.md` + a MEMORY.md index line.
7. `memstore_mark_done` pointer #1. Repeat for #2 (suppose it yields zero
   candidates → mark done, nothing written). Nudge count → 0 next session.
