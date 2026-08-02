---
name: roadmap
description: Use when a solo/long-haul personal project needs its GitHub-Issues roadmap created, reconciled, or updated — bootstrapping labels+issues for a project with none, checking roadmap drift against branches/commits at session start, recording done/next/blockers at session end, or migrating a project off a committed ROADMAP.md. Triggers include /roadmap, "set up a roadmap", "what's left on this project", "where are we", roadmap drift after merges.
---

# Roadmap (GitHub Issues)

Maintain a solo **personal** project's roadmap as **GitHub Issues** — the durable spine of
*what's done and what's next*, read on-demand (no committed `ROADMAP.md`, no per-session
auto-read tax). The convention + session discipline live in `rules/solo-project-roadmap.md`
(loaded every session); this skill is the **HOW**.

Projects you own and can write to. For a repo you don't own or can't write to, defer to
whatever tracker it already uses and stay read-only. Reconcile against git, not memory.

## Pick the action

- **No `now`/`next` labels yet** → Bootstrap.
- **Still has a committed `ROADMAP.md`** → Migrate.
- **Starting work / "where are we"** → Reconcile.
- **Wrapping up / handing off** → Update.

## The model

- `now` label — 1–3 open issues, in-progress workstreams.
- `next` label — open issues in dependency order, "blocked by #N" in the body.
- Done — **closed** issues (`gh issue list --state closed`).
- Deadline + progress visual — a **milestone** (e.g. "July 4 dogfood"); GitHub shows a
  native X/Y-closed progress bar on web + mobile. No generated HTML dashboard.

## Bootstrap (new project)

1. Confirm repo + remote: `gh repo view --json nameWithOwner`.
2. Create labels (idempotent — ignore "already exists"): `gh label create now`; `gh label create next`.
3. Gather real state: `git log --oneline -30`, `git branch -a`, `git worktree list`, plus repo-local memory/handoff/plan docs for workstream structure + dependency order.
4. **Show the planned issues and ask for correction** before creating — don't seed a guessed roadmap.
5. Create issues: one per workstream; the 1–3 active get `now`, the queued get `next` ("blocked by #N" in the body). Add a milestone for any deadline.

## Migrate (project still on a committed `ROADMAP.md`)

1. Read the existing `ROADMAP.md`; create `now`/`next` labels + a deadline milestone.
2. Create issues from the **live** `Now`/`Next` only — do NOT recreate the `Done` history
   (it stays in git history; closed issues become the new Done log going forward).
3. Retire the file machinery: delete `ROADMAP.md` and any generated dashboard
   (`docs/roadmap.html`); remove its sync git-hook (e.g. the `roadmap-drift` guard in
   `lefthook.yml`); drop any project-local SessionStart hook that auto-reads the roadmap.
4. Commit the retirement (`docs(roadmap): migrate to GitHub Issues`); the issues live
   outside the tree.

## Reconcile (session start)

1. `gh issue list --label now --state open` and `--label next`. 2. Diff against
`git log`/branches/worktrees. 3. Surface drift (a `now` issue already merged → close it; a
branch with no issue). 4. Fix issues to match reality **before** working.

## Update (session end)

- Close finished work: `gh issue close <#> -c "<one-line outcome>"`.
- Promote: started `next` → `gh issue edit <#> --add-label now --remove-label next`.
- Open what surfaced: `gh issue create --title … --label next --body "blocked by #N"`.
- Keep bodies lean — detail belongs in commits/PRs; the issue tracks the workstream.

## Keep it lean

`now` = 1–3 issues. `next` in dependency order, blockers named in bodies. Close
aggressively — closed issues are the queryable Done log, out of context until you ask.
