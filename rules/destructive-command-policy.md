# Destructive-command policy (enforced by hooks/guard-destructive.py)

A PreToolUse hook blocks the following Bash patterns **regardless of permission mode**
(including --dangerously-skip-permissions), because permission prompts alone failed on 2026-06-08:

- `rm -rf`/`-fr` targeting: `/`, `~`, `$HOME`, a bare `$VAR`, `..`, top-level globs, system dirs,
  or any path ≤2 levels under `~` (e.g. `~/projects`, `~/.local`).
- `git clean -fdx`, `find … -delete`/`-exec rm` over absolute/home roots,
  recursive `chmod/chown` over home/root, redirect-truncation over home dotfiles.

Allowed: narrow project-local deletes (e.g. `rm -rf node_modules`, `dist`) from inside a project.
The hook fails *open* on its own errors (never blocks legit work due to a hook bug).
