---
name: handoff
description: Use when a session is ending, context is running low, work is being paused mid-task, or the user asks for a "handoff", "continuation prompt", or "something to paste into a fresh session" - captures current state into a clipboard-ready prompt so a new session resumes without re-discovering context
---

# Handoff

## Overview

A handoff is mid/end-of-session state capture. Writing-plans is pre-work; handoff is the opposite bookend — the record of where *this* session landed so the *next* session doesn't rediscover it.

**Announce at start:** "I'm using the handoff skill to capture session state."

**Core principle:** A fresh session should be productive within one prompt. No re-exploration, no re-deciding.

## When To Run

Run this when ANY of these are true:

- The context warning fired (60% gentle / 70% urgent — stop-handoff-reminder.sh, exact API-usage numbers) or the user mentions compaction
- The user says "let's pause", "I need to stop", "handoff", "continuation prompt"
- End of working session with unfinished implementation
- About to switch to a parallel session on the same topic
- Plan mid-execution and you need to hand off to a fresh agent

**Do NOT run this for:** one-off questions, completed work with nothing pending, debugging sessions that resolved cleanly.

## The Gate Function

```
BEFORE writing the handoff:

1. RUN: git status + git log -5 --oneline + git diff --stat
2. DETECT phase: DISCOVER | PLAN | IMPLEMENT | TEST | REVIEW
3. SCAN transcript for: material decisions, unanswered questions, next command
4. IDENTIFY: plan file in docs/superpowers/plans/ if present
5. ONLY THEN: write the handoff document
```

Skipping step 1 = writing fiction. The handoff must reflect the actual VCS state, not the assumed state.

## If the repo is a personal project with a GitHub-Issues roadmap

When the repo is one of your own projects (your GitHub account, has a remote) and is not one you merely read, its roadmap lives in **GitHub Issues** (see the `roadmap` skill) — don't duplicate it into the handoff:

- **What's Next** → point at the issues (`gh issue list --label now` / `--label next`); do NOT restate the workstreams.
- Capture only the **session delta** not yet recorded: uncommitted work, dead-ends tried, open questions, decisions not yet written to an issue.
- Reconcile + update the issues (close done, promote next→now) as part of the handoff, then reference them from the Resume Command.

**In a repo you don't own:** full self-contained capture per the template below — defer to that project's own tracking, which is read-only to you. The GitHub-Issues roadmap convention is personal-projects-only.

## Output Location

Save to: `docs/superpowers/handoffs/YYYY-MM-DD-<short-topic-slug>.md` — **in the repo**, alongside `docs/superpowers/specs/` (brainstorming) and `docs/superpowers/plans/` (plans). Same semantic: a committed, repo-local artifact, never the global `~/.claude`.

Create `docs/superpowers/handoffs/` if missing. Path is repo-relative (in a worktree it lands in that worktree's tree, which is correct). Slug is 2-4 kebab-case words describing the work, not the phase. Good: `fault-status-service`. Bad: `implementation-work`.

## Document Structure

Use this template exactly. Section order matters — the fresh session reads top-down and the most actionable content must be earliest.

```markdown
# Handoff: <one-line topic>

**Date:** YYYY-MM-DD
**Phase:** DISCOVER | PLAN | IMPLEMENT | TEST | REVIEW
**Branch:** `<branch-name>` @ `<short-sha>`
**Plan:** `docs/superpowers/plans/<file>.md` (or "none")

## Resume Command

The exact command(s) the fresh session should run first:

```bash
<command>
```

## What Was Done

- <material change 1> — file:line if relevant
- <material change 2>

## What Did NOT Work

- <approach tried that failed> — <why; what to avoid repeating>

## What's Next

1. <next concrete action>
2. <action after that>

## Decisions Made

- **<decision>:** <what was chosen and why>. Alternative rejected: <...>.

## Open Questions

- [ ] <question> — blocked on: <what>

## Files Touched

| File | Purpose |
|------|---------|
| `path/to/file.go` | <one line> |

## VCS State

```
<output of git status, abbreviated>
<output of git log -5 --oneline>
```
```

## Field Rules

**Phase detection:** infer from what happened last — wrote a plan → PLAN complete, about to IMPLEMENT. Wrote code, no tests run → IMPLEMENT. Tests failing → TEST. PR opened → REVIEW.

**Decisions Made:** only *material* choices (architecture, naming across layers, library selection). NOT tool usage, NOT "I used grep first". If the user would disagree without seeing it, it belongs here.

**What Did NOT Work:** dead ends already explored — failed approaches, rejected libraries, configs that didn't take. Saves the next session from re-trying them. Omit the section only if nothing was tried and discarded.

**Open Questions:** each must name what unblocks it (person, spec, failing test, missing access). "TBD" alone is useless.

**Resume Command:** must be literally copy-pasteable. If no single command captures it, write a 2-3 line sequence. Not "continue where we left off" — that's what the whole doc is for.

## Clipboard-Ready Prompt

After saving the file, print to stdout a condensed version the user can paste into a fresh session:

```
Continuing work on <topic>. Handoff doc: docs/superpowers/handoffs/<file>.md

Branch: <branch> @ <sha>
Phase: <phase>
Next: <first item from What's Next>

Read the handoff doc before responding.
```

Keep under 10 lines. The fresh session reads the doc for detail — the prompt just points at it.

Printing this prompt is part of every handoff, not an optional extra — a handoff that ends without a pasteable prompt leaves the user to write one by hand.

## Autonomous next session

If the user wants the next session to continue autonomously/unattended (the `handoff-autonomously` skill, or phrasing like "next session runs on its own"): after printing the clipboard prompt, invoke the **goal-prompt** skill and emit its `/goal` line as a separate second paste message (see `handoff-autonomously` for the two-message format).

If the user asks only for the goal prompt ("give the /goal prompt"), use **goal-prompt** alone — no handoff doc.

## Optional: Issue Comment

If the project has a GitHub issue tied to this work (check for `issue/<number>-*` branch prefix or user-mentioned issue number):

```bash
gh issue comment <number> --body-file docs/superpowers/handoffs/<file>.md
```

Ask the user before running this. Never auto-comment on a repo the user does not own.

## Optional: Capture memory

If the session produced durable lessons (a failure→fix, a convention, a decision
the next session shouldn't relearn), write it directly into repo-local
`.claude/memory/` NOW while the session is fresh: one fact per file (frontmatter
`name:`/`description:`), plus an index line in `.claude/memory/MEMORY.md`. Check
existing entries for a near-duplicate first (grep, or `hooks/lib/memory-dedup.sh`
if a semantic backend is configured) — update the existing entry instead of
adding a second one on the same lesson. Nothing is committed automatically.

Skip this for sessions that produced no reusable lesson (the common case).

## What This Skill Does NOT Do

- **No silent memory writes.** Memory capture is a separate, opt-in step you do explicitly, never automatic.
- **No commits, no pushes.** The user commits. The handoff describes uncommitted state truthfully.
- **No Obsidian mirroring.** A separate hook handles that.
- **No tool-usage stats, token counts, or session metrics.** Noise.
- **No re-plan.** If scope changed mid-session, note the change in Decisions Made and let the next session re-run writing-plans if needed.
- **No summarization of the transcript.** The handoff is forward-looking.

## Red Flags - STOP

- Writing the doc without running `git status` first
- "Continue where we left off" as the resume command
- Decisions section empty when the session clearly made choices
- Open Questions with no "blocked on" clause
- Handoff longer than ~80 lines — you're summarizing, not handing off
- Ending the handoff without printing the clipboard-ready prompt

## Self-Check

Before declaring the handoff done, ask: *if I closed this session right now and opened a fresh one tomorrow with only this document, could I continue without asking the user anything?*

If no: fix the gap. Usually it's a missing resume command or an unstated decision.

## Gotchas

- **Stale file paths**: if Claude has been moving/renaming files during the session, verify each path still exists before writing it into the handoff. A resume prompt with a broken path is worse than no handoff.
- **Secrets in context**: never include pasted tokens, API keys, or credentials that appeared during the session. Strip them before handoff.
- **Do not claim completion**: the handoff is "paste this into a fresh session to resume", not "work is done". Say "paused" or "mid-task", not "complete".
- **Branch hygiene**: include `git status`/`git branch` output verbatim. Paraphrasing loses which files are staged vs modified, which matters on resume.

## Autonomous mode (`/handoff-autonomously`)

<!-- Merged from the handoff-autonomously skill 2026-08-16 (S7); that name
still resolves — its SKILL.md is a stub pointing here. -->

When the next session should continue **unattended**, produce the full handoff
above PLUS a ready-to-arm `/goal`:

1. **Derive the goal** with the `goal-prompt` skill (read its reference docs;
   build the condition from this handoff's "What's Next" + verification steps).
2. **Persist the goal in the doc** — append the full `/goal` line as a final
   `## Autonomous goal` section and commit it with the doc. Chat scrollback is
   lossy: a /goal that lived only in chat was once recovered from raw JSONL
   (2026-08-05). The committed doc is the durable copy.
3. **Walkthrough wiring** — the resume message must tell the goal session to:
   (a) present NO AskUserQuestion cards while the goal is active — queue
   human-shaped items per the `walkthrough` skill's unattended mode;
   (b) end by appending a completion report (**Accomplished / Walkthrough
   queue / Proposed next steps**) to the handoff doc;
   (c) on the user's first message after completion, proactively deal the
   walkthrough deck over that report.
4. **Deliver TWO paste messages** (a slash command only executes at the start
   of a message, and /clear wipes any active goal):

```
Message 1 — paste after /clear:

Continuing work on <topic>. Handoff doc: <path>

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
