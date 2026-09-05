---
name: sprint-wrap
description: >
  End-of-session ritual for a solo GitHub-Issues project: verify tracker state,
  and only if nothing is actionable run backlog-refinement → sprint-retrospective
  → sprint-plan → handoff, then commit and push the ceremony artifacts. Use when
  the user says "sprint-wrap", "wrap the sprint", "close out the session", or
  wants the end-of-session ceremonies run. Empty-queue sessions only — an
  actionable issue stops the wrap.
---

# /sprint-wrap — end-of-session ritual

Run the sprint-wrap for the current workspace. Bind every scrum concept per
the repo's `CLAUDE.md` and `rules/solo-project-roadmap.md`, not from memory:
story = GitHub issue on this repo, sprint = one `/clear`-scoped session,
capacity = one bounded solo chunk, DoR = "body specific enough to TDD from",
DoD = tests green + deployed + live-verified + issue closed with evidence.

The ceremony steps are the `backlog-refinement`, `sprint-retrospective` and
`sprint-plan` skills (from the `pm-skills` plugin). This skill sequences them
and adds the two things they don't know: the actionable-work gate and the
workspace's handoff/push conventions.

**Announce at start:** "Running sprint-wrap for <repo>."

## Step 0 — Verify state (never trust docs)

- `gh issue list --label now` and `--label next`; read the latest handoff doc;
  `git log -1 --oneline` + `git status`. Reconcile drift FIRST (memory-hygiene
  rule) — a tracker line that disagrees with git is fixed before anything else.
- Check every gate cited in open issue bodies (blocked-by refs, capstone gates,
  time gates): `gh issue view <n>` the referenced issues — a gate may have closed.

## Step 1 — Actionable-work check (the fork)

An issue is ACTIONABLE iff: open, not time-gated, not capstone/human-gated, and
all blocked-by refs closed. If any actionable issue exists → STOP the wrap,
surface it to the user, and do that work instead. This ritual is only for
empty-queue sessions; running ceremonies over a queue that still has work in it
is how a sprint ends with a nice retro and nothing shipped.

## Step 2 — backlog-refinement

- Grade each open issue against INVEST + this workspace's DoR; note the grade.
- Record cleared/changed gates IN the issue bodies (a dated "Gate status
  update" section, strikethrough the stale lines) so the next session reads
  current state from the tracker, not from a handoff.
- Close anything done, relabel now/next, file surfaced work as new issues.

## Step 3 — sprint-retrospective

- Window = commits since the last ceremony commit — find it in git log by
  subject (`chore(workspace): sprint-wrap` or `chore(workspace): handoff — …`),
  don't guess dates. Evidence = git log + closed issues + the latest handoff.
- Cover: numbers (commits, issues closed), prior action-item follow-through
  (applied / carry / retire — with evidence), what went well, what didn't, new
  action items (each with an owner-mechanism, not a wish).
- Artifact: `docs/superpowers/retros/YYYY-MM-DD-sprint-retro.md`.
- Bank any twice-proven lesson to memory via the `memory-capture` skill.

## Step 4 — sprint-plan (next sprint)

- 7 elements, solo-bound: goal (one sentence, outcome not output), capacity (one
  session), commit, stretch, dependencies (owner + ETA), risks (with mitigation),
  DoD per item. Any external-API item's DoD MUST include a live-verify task —
  a passing mock is not a verified behaviour.
- If the queue is fully gated: the plan names the unblock events + fallback; do
  NOT invent agent work to fill the session.

## Step 5 — handoff + push

- Invoke the `handoff` skill. Write the doc where THIS workspace's SessionStart
  hook reads handoffs from; if the workspace declares no such location, keep the
  handoff skill's default. Include: state summary, resume command, FIRST ACTION
  next session (= the sprint goal), VCS state.
- Update issues to match (Step 2 may already have done this — re-verify;
  status-flip rule: a task is not done until its tracker line flips).
- Commit the ritual artifacts (conventional commits, staged files only — never
  `git add -A`) and **push**. Foreground session: push main directly.
  Background session: push the worktree branch + draft PR, and flag that main
  needs the merge before the next session.

## Output

End with a one-screen summary: refinement grades, retro action items,
next-sprint goal, handoff path, push/PR state.
