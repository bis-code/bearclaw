---
paths:
  - "**/.claude/memory/**"
  - "**/memory-global/**"
  - "**/MEMORY.md"
  - "**/ERRORS.md"
---
# Memory Hygiene

<!-- Rewritten ~30 lines 2026-08-16 (S4); ERRORS.md format/prune policy moved
to memory-global/README.md. Path-scoped: loads when memory files are touched;
CLAUDE.md carries the one-line verify-before-citing reminder globally. -->

**Tiers:** `rules/` (committed, every session, behavior) · `memory-global/`
(committed, every session via hook, cross-cutting facts) · `<repo>/.claude/memory/`
(repo-local; committed in private personal repos, gitignored in public/work
repos). Native `~/.claude/projects/<cwd>/memory/` is a machine-local **inbox**
you drain by hand (see `handoff`'s "Optional: Capture memory" step) — never a
peer store. Legacy entries there migrate lazily when touched.

**Classify:** global if true *regardless of repo* (CLI behavior, conventions,
reusable fixes); repo-local if it only means something for that project.
Unsure → repo-local (promoting later is cheaper than over-globalizing).

**Verify before citing any structural claim from memory** — paths, invariants,
topology, process/deployment state. One cheap check (`ls`, `readlink`,
`git log -1`, `gh api`, `grep`, `docker inspect`) before recommending; a stale
claim costs 30 min to days, the check ~100 ms. After a compact/resume, run one
verification on the most load-bearing claim per MEMORY.md section. Never brief
a subagent on an unverified structural claim.

**Writing:** one entry, one fact · date verifications (`verified YYYY-MM-DD`) ·
link related entries with `[[name]]` · on contradiction, rewrite/delete in
place — never annotate · search before banking (no duplicate lessons under new
names).

**MEMORY.md is an index, not content:** `- [Title](slug.md) — hook (~150 chars)`
per line; bodies live in the linked files.

**Which journal?** "Would I grep this when something breaks?" → ERRORS.md.
"Would I cite this when designing?" → MEMORY.md. ERRORS.md entry format, append
gates, and prune policy: `memory-global/README.md` → "ERRORS.md convention".
