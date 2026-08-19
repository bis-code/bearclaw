# Solo-project roadmap (GitHub Issues)

Personal projects track state in GitHub Issues: `now` (1–3 active) /
`next` (dependency-ordered via "blocked by #N") / closed = history; milestones
for deadlines. No committed ROADMAP.md (the old one hit 91 KB and taxed every
session start). Session start: `gh issue list --label now` (+ `next`) and
reconcile against git state — fix drift first. Session end: close/relabel/open
issues — **a task is not done until its tracker line flips** (status-flip
rule). Label semantics + drift repair details: `skills/roadmap/SKILL.md`.
In a repo you only read — someone else's tracker owns it — skip this entirely
(`ROADMAP_SKIP_ROOTS` makes the session-start nudge silent there).
