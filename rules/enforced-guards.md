# Enforced guards (mechanical — hooks, not memory)

<!-- Merged from destructive-command-policy.md + background-agent-safety.md
2026-08-16 (S4). Incident narrative: memory-global/incident-2026-06-08-som-wipe.md -->

Two PreToolUse hooks enforce these regardless of permission mode:
`guard-destructive.py` blocks catastrophic deletes (`rm -rf` on `/`, `~`, bare
`$VAR`, paths ≤2 levels under `~`, system dirs; `git clean -fdx`; `find -delete`
over home/absolute roots; recursive `chmod`/`chown` over home; home-dotfile
truncation — narrow project-local deletes pass; fails open on its own bugs).
`pretooluse-dispatch-gate.sh` denies (once/session) background dispatch without
`isolation: "worktree"`.

What still needs model attention:
1. Background/autonomous agents always run worktree-isolated; never
   `bypassPermissions` for jobs that can touch paths above the project root.
2. No auto-updates while background agents run (the updater kills children
   mid-write).
3. Checkpoint (auto-commit/stash) unpushed work before starting a bg agent.
