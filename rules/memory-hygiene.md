# Memory Hygiene

Operating discipline for working with file-based memory (MEMORY.md + linked entries). Applies in every workspace.

## Memory tiers (where things live)

Three stores, by scope:

| Store | Location | Committed | Loaded | Holds |
|---|---|---|---|---|
| `rules/` | `claude-setup/rules/` | yes | every session | behavioral instructions |
| Global memory | `claude-setup/memory-global/` → `~/.claude/memory-global/` | scaffolding yes; your written content gitignored by default (opt in via .gitignore) | every session (SessionStart hook) | cross-cutting facts/failures |
| Repo-local | `<repo>/.claude/memory/` | gitignored by default; commit it in your private repos if you want machine portability | when cwd = that repo (hook) | project-specific facts/failures |

**Classification rule:** **Global** if it's true *regardless of which repo
you're in* — CLI/tool behavior, cross-project conventions, user preferences,
reusable failure fixes. **Repo-local** if it only means something *for this
project* — its decisions, layout, quirks, errors. When unsure → repo-local
(cheaper to promote later than to over-globalize).

The legacy `~/.claude/projects/<cwd>/memory/` location is deprecated; new
repo-local memory goes in `<repo>/.claude/memory/`. Old entries still load
natively and migrate lazily when next touched.

## Core rule

**Before citing any structural claim from memory — verify it.** Memory entries that lived through cycles of change can be silently false. They survive context compactions and continue to read as fact long after the underlying state shifted.

Structural claims include:

- File paths ("X lives at path Y")
- Invariants ("X is committed", "Y reads from Z")
- Topology ("symlinked from", "auto-built by")
- Active processes / sessions / teammates
- Deployment state ("DEV runs image X")
- Pipeline ownership ("secret Y is provisioned")
- Workflow status ("CI is green for X days")

## Verification mechanisms (cheap, fast — pick one)
<!-- Provenance: cost justification — a typical verification is one shell call, ~100ms; acting on a stale claim costs 30 min (re-deciding) to days (broken infrastructure). -->

| Claim type | Verification |
|---|---|
| File path | `ls <path>` |
| Symlink target | `readlink <path>` |
| Branch tip | `git log -1 --oneline <branch>` |
| GitHub state | `gh api <endpoint>` |
| Process state | `ps aux \| grep <pattern>` |
| Content claim | `grep <claim> <file>` |
| Runtime state | `docker inspect <container>` |

## Two checkpoints

**At session start** (especially after auto-compact or `/handoff` resume): run a "structural sanity sweep" — for each MEMORY.md section, identify the most load-bearing factual claim, run one verification call. ~30 seconds total. If a check contradicts memory: surface the drift, update the memory, then proceed with current reality.

**Before any teammate dispatch or large irreversible action:** if the brief cites a memory's structural claim, verify it first. Don't tell a teammate "the deploy works like X" if X is stale.

## Memory writing discipline

- **One entry, one fact.** Don't bundle "X is true" + "Y is true" + "the reason for Y" into one entry — they age at different rates.
- **Date the verification** in the entry body when banking ("verified 2026-MM-DD"). Lets future-you decide if it's still current.
- **Link related entries** via `[[name]]`. Memory becomes a graph; isolated entries decay faster than connected ones.
- **Remove on contradiction.** If today's reality contradicts a memory and you confirm reality is right — delete or rewrite the memory. Don't leave it as a footnote.

## MEMORY.md as index, not content

`MEMORY.md` is a one-line-per-entry index — never write content directly into it. Each entry is `- [Title](slug.md) — one-line hook (~150 chars).` The index gets loaded into every session; long entries truncate. Body lives in the linked file.

## Anti-patterns

- "MEMORY says X, therefore X is true" → always verify before recommending
- "I'll add a note next to it instead of fixing it" → memory entries should be updated in place, not annotated
- Citing a memory in a brief without checking the citation is still accurate
- Banking the same lesson twice under different names — search first, update if exists

## Related skills

- `superpowers:handoff` — handoff docs and memory complement each other: handoff = mid-cycle state, memory = cross-cycle lessons
- Repo-scope: each repo's `.claude/memory/` is the repo-bound version of this discipline (gitignored by default; committed where you've opted in — see "Memory tiers" above). The legacy `~/.claude/projects/<workspace>/memory/` path is deprecated.

## ERRORS.md convention

`ERRORS.md` is a failure journal alongside `MEMORY.md`, and follows the tiered
model (see "Memory tiers" above): the **global** journal at
`memory-global/ERRORS.md` is committed; a **repo-local** journal at
`<repo>/.claude/memory/ERRORS.md` follows its repo's memory policy (gitignored
by default; committed where you commit repo-local memory). The *convention* (format and
rules below) is shared across tiers; `install.sh` seeds an `ERRORS.md` if absent.

**Entry format (newest first):**
```
## [YYYY-MM-DD] <symptom> — <one-line resolution>
- **Trigger:** the command/condition that produced it (the searchable symptom)
- **Cause:** root cause, one line
- **Fix:** the exact command/flag/change that resolved it
- **Scope:** repo/tool/env it applies to (so it's prunable when that dies)
```

**Append only when ALL hold:** (1) you had to look it up or ask — it cost real
time; (2) it's environment/tooling-specific, not an in-flux code-logic bug;
(3) the fix is concrete and reusable.

**Do NOT log:** transient bugs in your own diff, anything already in MEMORY.md,
or "we discussed X" (that's a decision → MEMORY.md).

**Prune:** 200-line total-file cap (rotate oldest-resolved entries to
`ERRORS.archive.md` in the SAME tier's dir as `ERRORS.md` — it inherits that
tier's committed/ignored status;
never silent-truncate). Delete on scope-death (the repo/tool in `Scope:` is gone).

**Which file?** *"Would I grep this when something breaks?"* → ERRORS.md.
*"Would I cite this when designing?"* → MEMORY.md.
