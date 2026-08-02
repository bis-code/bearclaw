---
name: address-review-comments
description: Use when the user asks to address review feedback — GitHub PR review comments and/or in-code `REVIEW(claude):` markers. Triggers include "address my PR comments", "address review comments", "handle the review feedback", "do the REVIEW(claude) notes", or after a reviewer leaves comments on an open PR. Works one item at a time, smallest diff each, and never stages or commits.
---

# Address Review Comments

## Overview

Work through review feedback from two sources — GitHub **PR comments** and in-code
**`REVIEW(claude):` markers** — one item at a time. Each fix is the smallest diff
that satisfies the comment. **You never stage or commit** — the user reviews
`git diff` and commits themselves.

**Announce at start:** "I'm using the address-review-comments skill to work through the review feedback."

## Step 1: Detect mode

```bash
# Markers in the tracked tree:
"$HOME/.claude/bin/claude-review-markers"
# Open PR for the current branch (empty if none):
gh pr view --json number,headRepository,url 2>/dev/null
```

- Markers found, no open PR → **marker mode**.
- Open PR, no markers → **PR mode**.
- Both → tell the user both exist; default to doing **markers first, then PR**, unless they pick one.
- Neither → report "no review feedback found" and stop.

## Step 2 (PR mode): build the worklist + guard the account

```bash
# Account guard — the ~/.zshrc gh() wrapper auto-switches by cwd, but verify:
gh api user --jq .login
gh pr view --json number,headRepository,url
```

If the logged-in login does not plausibly match the PR repo owner, **stop and tell
the user** (wrong gh account for this repo) rather than acting blind.

Fetch comments (review threads + inline):

```bash
PR=$(gh pr view --json number --jq .number)
OWNER_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
gh api "repos/$OWNER_REPO/pulls/$PR/comments" \
  --jq '.[] | {id, file: .path, line: (.line // .original_line), reviewer: .user.login, body: .body}'
gh pr view --json reviews --jq '.reviews[] | select(.body != "") | {reviewer: .author.login, body: .body}'
```

Build a worklist of `{file, line, reviewer, body}` (keep each comment `id` for replies).

## Step 3 (marker mode): the worklist is the helper output

`{file, line, instruction}` rows from `claude-review-markers`.

## Step 4: Address one item at a time

For EACH worklist item, in order:

1. **Read the file region** (the line + surrounding context). Understand the ask.
2. **Make the smallest diff** that satisfies it. Scope discipline (`rules/execution-discipline.md`):
   touch only what the comment names; do not refactor adjacent code; do not remove
   unrelated screens/routes/fields. If the fix would exceed the named scope, **skip
   it and record why** for the summary — do not widen silently.
3. **Marker mode only:** in the same edit, **remove the `REVIEW(claude):` marker**
   (the tagged line, plus any obvious continuation comment lines that belong to it).
4. If the comment is unclear or you disagree on technical grounds, **do not guess** —
   mark it `needs-input` with a one-line question for the summary.

Verify after each edit where cheap (the file still parses / the relevant test passes).

## Step 5: NEVER stage or commit

Do not run `git add`, `git stage`, or `git commit`. Leave every change unstaged.
The user reviews `git diff` and commits.

## Step 6: Summary

Print a table:

| Item | File:line | Status | Note |
|------|-----------|--------|------|
| ...  | a.go:42   | addressed | renamed `foo`→`bar` |
| ...  | b.ts:10   | skipped | out of scope: would touch unrelated module |
| ...  | c.py:7    | needs-input | which validation lib should this use? |

**PR mode — print copy-paste reply/resolve commands** (do NOT auto-reply):

```bash
# Reply to a review comment thread (use the comment id from Step 2):
gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment_id>/replies -f body='Done — see latest diff.'
# Resolve a thread is GraphQL only (gh api graphql ... resolveReviewThread) — print, don't auto-run.
```

End by telling the user: changes are unstaged — review `git diff` and commit when ready.

## Red flags — STOP

- About to `git add`/`commit` → STOP; the user stages.
- Fix growing beyond the comment's scope → STOP; skip + record, don't widen.
- gh account doesn't own the PR repo → STOP; surface it.
- Marker left in a file after you addressed it → remove it.
