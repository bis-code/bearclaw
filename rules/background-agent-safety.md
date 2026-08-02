# Background / autonomous agent safety

Direct cause of a real 2026-06-08 data-loss incident: a background daemon job ran
with `--permission-mode bypassPermissions` AND worktree isolation disabled
directly on the live projects tree, then was killed mid-operation by a concurrent
CLI self-update. It wiped the projects root, `~/.local`, and shell rc files. No
backup existed. Every rule below exists because of that.

Rules:
1. Background/daemon agents MUST run with worktree isolation (`bgIsolation` != `none`)
   so they operate on a throwaway copy, never the live tree. **Mechanically enforced** by
   `hooks/pretooluse-dispatch-gate.sh` (bg Agent/Task dispatch without
   `isolation:"worktree"` is denied once/session); `hooks/guard-destructive.py` is
   the backstop that blocks the catastrophic delete even when isolation is bypassed.
2. Do NOT use `bypassPermissions` for background jobs that can touch paths above the
   project root. Keep the destructive-command guard hook active for all sessions.
3. The auto-updater MUST NOT run while background agents are active (it deletes the
   running binary and SIGKILLs children mid-write). Gate updates on an idle daemon.
4. Before starting a background agent, check any project with unpushed work into a
   commit or stash first — a throwaway worktree protects the live tree, but a crash
   mid-run can still cost uncommitted changes in that worktree's copy.
