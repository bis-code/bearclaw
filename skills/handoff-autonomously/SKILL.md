---
name: handoff-autonomously
description: Use when the user types /handoff-autonomously or asks for a handoff where the next session should continue autonomously or unattended after /clear — a full handoff plus a ready-to-paste /goal line.
---

# Handoff (autonomous next session)

Composite skill: a normal handoff whose paste block also arms the next session
with a `/goal` condition so it runs to completion without per-turn prompting.

1. **REQUIRED SUB-SKILL: `handoff`** — run the full flow (gate function,
   handoff doc, clipboard-ready prompt).
2. **REQUIRED SUB-SKILL: `goal-prompt`** — read its reference docs, then derive
   the condition from the handoff's "What's Next" and its verification steps.
3. **Walkthrough wiring** — Message 1 must instruct the goal session to:
   (a) never present AskUserQuestion cards while the goal is active — queue
   human-shaped items (manual steps, unverifiable outcomes, unauthorized
   decisions) instead, per the `walkthrough` skill's unattended mode;
   (b) end the run by appending a structured **completion report** to the
   handoff doc with three sections — **Accomplished / Walkthrough queue /
   Proposed next steps**;
   (c) on the user's first message after the goal completes, proactively deal
   the `walkthrough` deck over that report (recap → queue → next steps).
4. Final output is TWO paste messages, clearly labeled — a slash command only
   executes at the start of a message, so the `/goal` line must be sent on its
   own, and after `/clear` (which wipes any active goal):

```
Message 1 — paste after /clear:

Continuing work on <topic>. Handoff doc: docs/superpowers/handoffs/<file>.md

Branch: <branch> @ <sha>
Phase: <phase>
Next: <first item from What's Next>

Read the handoff doc before responding.

While the goal is active: no AskUserQuestion cards — queue manual steps,
unverifiable outcomes, and unauthorized decisions instead (walkthrough skill,
unattended mode). When the goal completes: append a completion report
(Accomplished / Walkthrough queue / Proposed next steps) to the handoff doc,
and on my first message afterward start the walkthrough deck over it.

Message 2 — send once message 1's turn finishes:

/goal <condition from goal-prompt>
```

Remind the user to pair with auto mode if the run must be truly unattended —
/goal starts turns but does not change permissions.
