---
name: memory-capture
description: Use when distilling a session into durable memory — "capture this lesson", "bank what we learned", or at handoff/session end. Distills candidate lessons from the session in context, dedups each against the live memory backend, writes only what the user accepts, and verifies each write is actually retrievable.
---

# Memory Capture

## Overview

Turn session experience into durable memory behind a review gate. Shell hooks
cannot call an LLM — this skill is where Claude does the distillation they
cannot: read the session, distill candidates, dedup, write what the user
accepts, then prove each one is reachable.

**Announce at start:** "I'm using the memory-capture skill to distill and stage memory."

**Core principle — distill → dedup → accept → write → VERIFY.** Nothing reaches
memory without an explicit accept, and nothing counts as captured until it has
been retrieved through the running recall hook.

**Scope:** the session in context. The old deferred-drain path over a
SessionEnd capture queue is gone with that machinery (it promoted 0 of 16
candidates in its lifetime). Don't go hunting for a queue.

## 1. Distill

Produce 0–N candidates from the session. Each is ONE fact (memory-hygiene: one
entry, one fact). Good shape:

- a reusable failure→fix (ERRORS.md shape), or a decision/convention (own file)
- concrete and reusable, not "we discussed X"
- dated: "verified YYYY-MM-DD" in the body

**Zero candidates is a valid outcome — say so and stop.** Prefer four real
lessons to a filled quota; a small corpus pays for every duplicate twice, once
in an injected slot and once in the false confidence of reading the same claim
from two places.

**Skip anything a mechanism now enforces.** If the lesson became a test, a size
guard, or a rule in a skill, the mechanism IS the memory — a prose copy only
adds a second thing to keep in sync. Bank the ones nothing enforces.

## 2. Dedup — and do not trust the verdict alone

```sh
sh "$HOME/.claude/hooks/lib/memory-dedup.sh" <index-name> "<candidate text>"
# -> "<max-jaccard> SKIP" | "<max-jaccard> NEW" | "0.0 NEW UNVERIFIED"
```

Index names come from `hooks/lib/memory-roots.sh`: the global tier is
`memroots_global_index` (e.g. `claude-memory-global`), a repo tier is
`<main-worktree-basename>-memory`.

- `SKIP` (≥ `MEMORY_DEDUP_THRESHOLD`, 0.6): a near-duplicate exists. Don't add a
  second entry; if the existing one is stale, update it in place.
- `NEW`: novel **by word overlap only**.
- `NEW UNVERIFIED`: the search could not run. The verdict is a guess — grep the
  target memory dir for 2–3 distinctive terms before trusting it.

**The check is Jaccard on word tokens, so it catches near-verbatim duplicates
and misses semantic ones.** Measured 2026-08-31: the candidate "positive control
your checks: a check you have never seen fail has not been tested" scored
**0.2903 NEW** while that exact lesson was already banked, in different words,
in `ERRORS.md`. Writing it would have produced a duplicate the tool called novel.

So: **read the top hits yourself and judge.** `bin/claude-memory-recall
"<candidate topic>"` or a grep of the memory dir. The tool's verdict is one
input, not the decision.

## 3. Choose the tier

Default is **repo-local** (`<main-worktree>/.claude/memory/`). Promote to global
(`memory-global/`) only if the lesson is true regardless of repo. Resolve the
MAIN worktree — memory lives there, not in a linked one:

```sh
GIT_COMMON=$(git -C "<cwd>" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
MAIN_ROOT=$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || echo "<cwd>")
```

## 4. Gate — one AskUserQuestion card per candidate

Options: **Keep** · **Edit** · **Drop**. On Edit, re-run dedup on the revised
text. NEVER auto-accept.

Under an active `/goal` or any unattended run, deal **no cards**: queue the
candidates into the report's Walkthrough queue instead and stop. A card with
nobody there stalls the run.

## 5. Write

`<mem-dir>/<slug>.md`, frontmatter per memory-hygiene:

```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary, used for recall relevance>
metadata:
  node_type: memory
  type: user | feedback | project | reference
  originSessionId: <session id>
---
```

Body: the fact, then **Why:** and **How to apply:** for feedback/project types.
Link related entries with `[[slug]]`. Then add one pointer line to the tier's
`MEMORY.md` index — `- [title](slug.md) — hook` — never the content itself.

**Global memories live in this repo**, so they reach `~/.claude` only via
`install.sh` (copy-on-install). Writing the repo file is not the same as making
it live.

## 6. Verify — retrievable, not merely written

A memory nothing can retrieve is not captured. Rebuild, then ask for it through
the hook that will actually serve it:

```sh
sh hooks/lib/membackend-local-embed.sh build <index-name> <corpus-dir>
printf '{"prompt":"<a question this memory answers>","cwd":"<repo>"}' \
  | sh hooks/userpromptsubmit-memory-recall.sh | jq -r '.hookSpecificOutput.additionalContext'
```

Confirm the new content appears. If it doesn't, check the backend directly
(`membackend-local-embed.sh search …`) to tell "not indexed" apart from "indexed
but out-ranked" — they need different fixes, and only the first is a bug.
