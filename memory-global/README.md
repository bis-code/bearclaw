# Global memory tier

Cross-cutting facts/lessons/failures that are true **regardless of which repo
you're in** — CLI/tool behavior, cross-project conventions, reusable failure
fixes. Loaded into every session via `hooks/sessionstart-load-memory.sh`.

Repo-specific knowledge goes in that repo's gitignored `.claude/memory/` instead.
See `rules/memory-hygiene.md` for the classification rule.

- `MEMORY.md` — index (one line per entry)
- `ERRORS.md` — global failure journal (newest first)
- `<slug>.md` — one fact per file, frontmatter: `name`, `description`, `metadata.type`

## ERRORS.md convention

<!-- Moved from rules/memory-hygiene.md 2026-08-16 (S4) — policy reference,
not per-session behavior. -->

The failure journal exists per tier: the **global** journal here is committed;
a **repo-local** `<repo>/.claude/memory/ERRORS.md` follows its repo's memory
policy. `install.sh` seeds one if absent.

**Entry format (newest first):**
```
## [YYYY-MM-DD] <symptom> — <one-line resolution>
- **Trigger:** the command/condition that produced it (the searchable symptom)
- **Cause:** root cause, one line
- **Fix:** the exact command/flag/change that resolved it
- **Scope:** repo/tool/env it applies to (so it's prunable when that dies)
```

**Append only when ALL hold:** (1) it cost real lookup time; (2) it's
environment/tooling-specific, not an in-flux code-logic bug; (3) the fix is
concrete and reusable. Do NOT log transient bugs in your own diff, anything
already in MEMORY.md, or decisions (those go to MEMORY.md).

**Prune:** delete on scope-death only. **No length cap** — the corpus stager
splits this file per `## ` entry, so length costs nothing at read time.
**Never rotate entries into ERRORS.archive.md:** the stager excludes it, so
archiving removes an entry from recall entirely while looking safely filed.
