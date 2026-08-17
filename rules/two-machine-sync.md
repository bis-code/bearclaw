# Multi-machine sync

The repo is the only sync channel. Sitting down at a possibly-stale machine:
run `bin/claude-setup-sync` (pull → install → doctor; refuses on dirty tree).
Capture lessons locally; promote cross-machine ones with
`hooks/lib/memory-promote.sh` — **a promotion reaches other machines only
after commit + push**, so push memory-global/settings/rules changes at session
end (the session-start drift nudge names anything uncommitted/unpushed).
Re-running install.sh after pull is only needed for structural changes —
symlinks make pulled file edits live automatically.
