---
name: goal-prompt
description: Use when the user asks for a "/goal prompt", a goal condition, or a completion condition for Claude Code's built-in /goal command — "give the /goal prompt", "write a goal for the next session", "what should the goal be" — or as the final step of an autonomous handoff (handoff-autonomously).
---

# Goal Prompt

## Overview

Produces a ready-to-paste `/goal` line for Claude Code's built-in `/goal`
command, which keeps a session working across turns until a small evaluator
model confirms a completion condition.

**`/goal` is newer than most models' training data — never write a condition
from memory.** REQUIRED: read [references/goal-docs.md](references/goal-docs.md)
before writing the prompt.

**Announce at start:** "I'm using the goal-prompt skill."

## When invoked standalone

The user asked for the goal prompt only — deliver the `/goal` line and stop.
No handoff doc, no session summary, no extra prose beyond the notes below.

## The output

One pasteable block containing a single `/goal` line built from four parts,
in order:

```
/goal <one measurable end state>, verified by <the check Claude runs and shows>. Constraints: <what must not change>, shown by <its own check>. Stop after <N> turns if not met.
```

1. **End state** — one measurable fact: tests pass, build exits 0, queue
   empty, file count under budget. Derive it from the session's "What's Next"
   / acceptance criteria, not from vibes. If the task wording and the
   pass/fail check name the same event ("finish X" / "tests for X pass"),
   state only the check — the task wording is context, not a second condition.
   If the end state hands off to human verification (device testing, review),
   it must also require the downstream artifact that verification depends on
   — a build uploaded, a deploy live, a package published — or the goal ends
   "complete" with nothing to verify against.
   If the remaining work includes human-input items (manual steps, decisions,
   unverifiable outcomes), they must not block the goal: the end state counts
   the **written walkthrough queue** (see the `walkthrough` skill) as the
   deliverable for those items.
2. **Stated check** — the command whose output proves it (`npm test` exits 0,
   `git status` clean). The evaluator only reads the transcript — the
   condition must be provable by Claude's own surfaced output.
3. **Constraints** — anything that must NOT change on the way there, each
   with its own transcript proof ("`git diff --stat` shows no other test file
   changed"). An unproven constraint forces the evaluator to guess.
4. **Bound** — a turn clause so a stuck goal terminates. Scale N to the work:
   ~10 for a bounded fix, ~20 for a feature slice, 30–40 for a migration or
   backlog drain.

After the block, add at most two one-line notes when they apply:
- "Pair with auto mode for unattended runs — /goal doesn't change permissions."
- "Set it in the fresh session after /clear (a /clear removes any active goal)."

## Common mistakes

| Mistake | Fix |
|---|---|
| Vague end state ("improve the tests") | Name the measurable fact ("all tests in `test/auth` pass") |
| Restating the task alongside its check ("finish X and tests pass") | One event, one clause — keep the check, drop the restatement |
| Constraint asserted with no proof | Pair every constraint with the check that shows it held |
| End state stops at a verify gate whose prerequisite artifact is never produced | Include the build/deploy/publish step the verification needs |
| Proof the evaluator can't see (file contents never printed) | State the check whose output lands in the transcript |
| Goal blocks on a manual step or human decision | Queue it (walkthrough queue = the deliverable); the goal completes with the queue written |
| No bound | Always append "stop after N turns" |
| Multiple unrelated goals in one condition | One goal per session — pick the one end state, or sequence sessions |
| Condition >4,000 chars | Trim to end state + check + constraints + bound |
