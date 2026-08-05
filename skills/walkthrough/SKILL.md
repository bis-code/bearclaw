---
name: walkthrough
description: This skill should be used when the user asks to go through items "one by one", "walk me through" steps/findings/decisions, "present next steps/findings/decisions with AskUserQuestion", go through "manual steps" or "manual verification" together, digest a long report or findings interactively, review "what has been decided" or "what has been accomplished", or triage a checklist/backlog item-by-item — deals one AskUserQuestion card per item, locks each answer, and syncs outcomes to trackers at the end.
---

# Walkthrough

## Overview

Turn an in-context item-list or long text — plan steps, next steps, review
findings, manual/verification steps, open decisions, a completion report, a
checklist — into a card deck: exactly **one AskUserQuestion card per item, one
per turn**. The user answers on cards (fast, mobile-friendly) instead of
reading a prose dump and replying in text.

**Announce at start:** "Walkthrough: N items — D digest, X recap, Y
manual/verify, Z decisions, W next steps." Then deal the first card.

## Scope: in-session only

Operate only on material already in context (just produced, or read for
another reason). This skill is **not a resume mechanism**: cross-`/clear`
continuity belongs to `handoff` / `handoff-autonomously`, whose pasted prompt
may itself instruct the fresh session to start a deck. Never go hunting in
files for something to walk through.

## Step 1 — Partition

Split the material into typed items and deal in this order: **digest → recap
→ manual/verify → decisions → next steps** (digest first — when the material
is a long text, digesting it is usually where the other item types surface;
then cheap confirms, judgment last). Digest cards follow the source text's own
order.

| Type | Material | Options (≤4, recommended first) | After answer |
|---|---|---|---|
| **Digest** | a section of long text | Next / Discuss / Act on this | Discuss → see the Discuss rule below |
| **Recap** | done / already-decided items | Confirm / Correct | Correction updates the record before continuing |
| **Manual step** | user must do it by hand | Done / Blocked / Skip | Done → verify-when-cheap; Blocked → capture the blocker, continue |
| **Verification** | an outcome to check | Pass / Fail / Can't check | Fail → offer `superpowers:systematic-debugging` |
| **Decision** | open choice | 2–4 real options with trade-offs | Locked in; never re-opened |
| **Next step** | proposed work | Do now / Defer / Drop / Discuss | Do-now items execute after the deck, unless one blocks a later card; Discuss → see the Discuss rule below |

Outcomes not called out above (Next, Confirm, Skip, Can't check, Pass) simply
advance to the next card.

**Discuss rule:** pause dealing and converse in plain text until the user
signals resolution ("continue", "next"). Then re-deal the same card — unless
the discussion already answered it, in which case record the verdict and
advance.

## Card hygiene

- One card per turn (Conversation Pacing). Never bundle unrelated items into
  one call's multiple-question slots.
- The question text restates the item fully — readable on mobile without
  scrolling back.
- ≤4 options; recommendation first, labeled "(Recommended)"; `multiSelect`
  only for genuinely non-exclusive sets.
- Long item? Distill to ≤3 sentences on the card; the full text stays in the
  chat above.

## Verify-when-cheap

After a manual step's "Done": if the step has an observable effect checkable
in 1–2 read-only calls (file exists, endpoint responds, CI status, setting
present), check it before advancing. On mismatch, re-present the card with the
evidence found. No observable effect → advance on the user's word.

## Exit — decision log + tracker sync

When the deck completes, or the user bails mid-way:

1. Print a compact decision log: item → verdict → follow-up. Mark unanswered
   items "not reviewed".
2. Sync whatever tracker is live: the session task list (TodoWrite/TaskCreate,
   whichever the harness provides — one entry per unresolved or deferred item,
   not a single bundled entry), GitHub roadmap issues (`now`/`next` labels per
   the solo-project-roadmap rule), or the pending handoff doc. Then execute
   the "Do now" items; "Defer" lands in `next`; "Drop" closes with a one-line
   reason.

## Unattended mode (`/goal` sessions)

Under an active `/goal` in an unattended session, present **zero cards** — a
card stalls the run with nobody there to answer. Instead, queue anything
human-shaped (manual steps, outcomes that couldn't be verified, decisions not
pre-authorized) into a **Walkthrough queue** section of the completion report
/ handoff doc. Run verify-when-cheap before queuing: items an automated check
confirms go straight into the report's Accomplished section; only items that
fail, or have nothing observable to check, land in the queue. The queue is a
*deliverable, not a blocker* — the goal completes with items in it. When the
user's first message arrives after goal completion, proactively deal the deck
over the report (recap → queue → next steps, each queue entry dealt as its
original card type: manual step, verification, or decision) — don't wait to
be asked.
