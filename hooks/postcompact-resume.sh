#!/bin/sh
# postcompact-resume.sh — runs from PostCompact hook (user scope, all projects).
#
# After an AUTO compaction, injects a NEUTRAL pointer at the pre-compact
# snapshot (git/todo state the native summary tends to lose) and a reminder
# that path-scoped rules are not re-injected after compaction. The old
# "resume immediately, do not ask the user" directive was dropped 2026-08-16
# (D4): native compaction continues the turn with a structured summary, and
# the push fought legitimate judgment about when to pause.
#
# Always exits 0 — compaction completion must never be blocked.

set +e

# Manual /compact is the user's own action; stay silent there.
INPUT=$(cat 2>/dev/null)
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // empty' 2>/dev/null)
[ "$TRIGGER" = "manual" ] && exit 0

LATEST=$(ls -1t "${SNAPSHOT_DIR:-$HOME/.claude/handoffs}"/precompact-*.md 2>/dev/null | head -1)
[ -n "$LATEST" ] || exit 0   # nothing to point at — the summary stands alone

MSG="Context was auto-compacted; the compact summary above is the continuity source."
MSG="$MSG A pre-compact snapshot with git branch/working-tree/todo state was saved at $LATEST — consult it if the summary lost repo-state detail."
MSG="$MSG If any rules are path-scoped to files in flight (paths: frontmatter), re-read them: scoped rules are not re-injected after compaction."

jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "PostCompact",
    additionalContext: $msg
  }
}'

exit 0
