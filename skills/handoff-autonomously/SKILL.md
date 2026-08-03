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
3. Final output is TWO paste messages, clearly labeled — a slash command only
   executes at the start of a message, so the `/goal` line must be sent on its
   own, and after `/clear` (which wipes any active goal):

```
Message 1 — paste after /clear:

Continuing work on <topic>. Handoff doc: docs/superpowers/handoffs/<file>.md

Branch: <branch> @ <sha>
Phase: <phase>
Next: <first item from What's Next>

Read the handoff doc before responding.

Message 2 — send once message 1's turn finishes:

/goal <condition from goal-prompt>
```

Remind the user to pair with auto mode if the run must be truly unattended —
/goal starts turns but does not change permissions.
