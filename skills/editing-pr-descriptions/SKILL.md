---
name: editing-pr-descriptions
description: Use when the user asks to update an existing PR's description or title, restructure a PR body, write a PR summary from accumulated commits, or apply changes via `gh pr edit`. Triggers include "update PR description", "rewrite PR body", "fix PR title", or completing a long-running branch where the original PR description is stale.
---

# Editing PR Descriptions

## Overview

When the user asks to write or update a PR description, gather the actual change set first, then write a structured body grouped by theme. Apply with `gh pr edit --body-file` and iterate from a temp file. Default to a minimal body — no filler sections the user didn't ask for.

## Workflow

### 1. Read current state

```bash
gh pr view <NUM> --json number,title,body,baseRefName,headRefName
```

Captures existing title/body and the merge base for the next step.

### 2. Get the actual commit list

```bash
git log --oneline <baseRefName>..HEAD
```

The full commit list is your source of truth for what the PR contains. Don't paraphrase from memory or recent conversation context — branches accumulate work over weeks.

### 3. Group commits by theme

Skim the commits and bucket into 3-6 themes the reader can scan. Common groupings:

- New endpoints / features
- Refactor (architectural / cleanup)
- Fixes (bugs, drift)
- Docs / spec changes
- Tests + chores

### 4. Write body to a temp file

Use `/tmp/pr-<NUM>-body.md` so you can iterate on user feedback without rewriting from scratch. Structure:

```markdown
## Summary

One paragraph: what the PR does and why. Lead with the user-facing change.

## Key changes

### <Theme A>
- Bullet 1
- Bullet 2

### <Theme B>
- ...
```

### 5. Apply with `gh pr edit`

```bash
gh pr edit <NUM> --title "<new title>" --body-file /tmp/pr-<NUM>-body.md
```

Drop `--title` if existing title is correct. Always use `--body-file` (not `--body "<inline>"`) — multi-line markdown breaks shell quoting.

### 6. Iterate on feedback

When the user asks to remove a section, edit `/tmp/pr-<NUM>-body.md` and re-run `gh pr edit --body-file`. Don't reconstruct the whole body.

## What to OMIT by default

These sections were repeatedly stripped by users when added speculatively:

- **No "Test plan" checklist.** Add only when the user explicitly asks.
- **No "Deferred / not in scope"** list. The PR body should describe what IS in the PR, not what isn't.
- **No `Co-Authored-By: Claude`** trailer.
- **No "Generated with Claude Code"** or any AI attribution.
- **No emoji** in section headers unless requested.

## Title guidance

- Keep under ~70 characters.
- Describe what the PR DOES, not what work happened in it.
- Multiple loosely-related themes joined with `&`, e.g. `Pull report endpoints & Push report factoring & OpenAPI alignment`.
- Do NOT prefix with conventional-commit type (`feat:`, `fix:`); that pattern is for commit messages, not PR titles.

## Permissions consideration

`gh pr edit` is a write operation. Some workspaces block it by default. If blocked:

1. Inform the user and write the proposed title + body to a file inside the
   repo (e.g. a gitignored scratch path). Ask where it should go rather than
   assuming a location outside the repo — this skill does not know your notes
   setup and must not invent a path on your machine.
2. Provide the exact `gh pr edit <NUM> --title "..." --body-file <path>` invocation.
3. Apply only after explicit user authorization.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing body from session memory | Run `git log <base>..HEAD` against the actual merge base |
| `gh pr edit --body "<text>"` inline | Always `--body-file /tmp/pr-<NUM>-body.md` |
| Adding "Test plan" / "Deferred" by default | OMIT both unless asked |
| Burying user-facing change in section 4 | Lead with the externally visible change |
| Listing every commit verbatim | Group commits by theme; use commit subjects as bullets |
| First person ("I added...") | Third person / imperative ("Adds...", "Add...") |

## Quick reference

```bash
# 1. Read current state + merge base
gh pr view <NUM> --json title,body,baseRefName

# 2. Commit list since base
git log --oneline <base>..HEAD

# 3. Write/edit body file
$EDITOR /tmp/pr-<NUM>-body.md

# 4. Apply
gh pr edit <NUM> --title "<title>" --body-file /tmp/pr-<NUM>-body.md
```
