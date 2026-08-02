---
name: agent-self-evaluation
description: Use before declaring a research, review, audit, design, or synthesis deliverable done — score the output against a 5-axis rubric with evidence and fix the weakest axis before returning
---

# Agent Self-Evaluation

Before returning a non-trivial deliverable (research summary, review, audit, design brief, synthesis), score it against the rubric below. This is **output-quality** self-assessment — the complement to `superpowers:verification-before-completion`, which verifies *code behavior*, not *whether the answer is good*.

**Announce:** "Scoring this against the self-evaluation rubric before returning."

## The rubric

Score each axis 1–5. **Cite evidence from your own output for the score** — a bare number is not allowed.

| Axis | Asks | Evidence to cite |
|---|---|---|
| **Accuracy** | Is every load-bearing claim verified, not assumed? | The check you ran per claim (grep / curl / ps / file read) |
| **Completeness** | Whole asked scope covered — no silent gaps or dropped sub-questions? | Each part of the request mapped to a part of the answer |
| **Clarity** | Can the reader act without re-reading? | Structure used: lead-with-answer, tables over prose |
| **Actionability** | Is the next step concrete and owned? | The specific command / file / decision handed back |
| **Conciseness** | Any padding — filler, restated prompt, hedging? | What you cut, or could still cut |

## The rule

- Any axis ≤3 → **fix it before returning**, don't ship-and-caveat.
- Fix the lowest axis first, then re-score.
- Distrust a straight-5 self-score — if every axis looks perfect you probably didn't look hard. Name the weakest axis even when all pass.

## When to skip

Trivial turns — a one-line answer, a single mechanical edit, a yes/no. The rubric is for deliverables someone will act on, not for conversation.
