# Solo-project roadmap (GitHub Issues)

Solo, long-haul personal projects have no PRs/teammates/reviews to impose structure
from outside — so state slips between sessions. The durable spine is the project's
**GitHub Issues**. Distinct from: `memory` (lessons), `ERRORS.md` (failures),
`handoff` (ephemeral resume prompt), `writing-plans` (one-task plan). Issues are the
living source of truth for *what's done and what's next*; those others feed it.

**Scope: projects you own and have write access to.** For a repo you cannot
write to, defer to whatever tracker that project already uses and stay
**read-only** — never open or edit its issues.

## The model (read on-demand — no committed `ROADMAP.md`)

- `now` — open issues labeled `now`: 1–3 in-progress workstreams.
- `next` — open issues labeled `next`, **dependency order** via "blocked by #N" in the body.
- Done — **closed** issues (`gh issue list --state closed`), the queryable history.
- Deadlines — a milestone (e.g. "July 4 dogfood").
- **No committed `ROADMAP.md`.** Issues are read on demand (`gh issue list`), never
  auto-loaded every session — the old file grew to 91 KB and taxed every session start.
  Detail lives in the issue body + commits, not in context.

## Discipline

- **Session start:** `gh issue list --label now` (and `--label next`) to see current work;
  reconcile against `git log`/branches/worktrees (verify-source-of-truth). Fix drift first.
- **Session end:** update issues — close finished ones, open/relabel what surfaced, re-note
  blockers in bodies. No commit ceremony; issues live outside the tree.
- New personal project with no roadmap → create `now`/`next` labels + the first issues from
  current git state before the next workstream.
