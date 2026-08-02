#!/bin/sh
# postcompact-resume.sh — runs from PostCompact hook (user scope, all projects).
#
# Auto-resumes work after context compaction by injecting an instruction
# telling Claude to read the compact summary, find the in-flight task, and
# continue without waiting for user input. Pairs with precompact-snapshot.sh:
# if a snapshot file exists, points Claude at it for git/repo state.
#
# Always exits 0 — compaction completion must never be blocked.

set +e

# Hook payload includes a trigger field ("manual" for /compact, "auto" for the
# autoCompactWindow-triggered path). Manual compacts are the user's choice;
# they'll drive the next turn themselves and shouldn't be steamrolled by an
# auto-resume directive. Skip for explicit manual; fire for "auto" and unknowns.
INPUT=$(cat 2>/dev/null)
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // empty' 2>/dev/null)
[ "$TRIGGER" = "manual" ] && exit 0

SNAPSHOT=""
LATEST=$(ls -1t "$HOME/.claude/handoffs"/precompact-*.md 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
    SNAPSHOT="$LATEST"
fi

MSG="The conversation was just auto-compacted (no manual /handoff was run beforehand). Resume the in-flight task immediately without asking the user what to do next."
MSG="$MSG The compact summary above is your source of truth — read it carefully, identify the most recent concrete step or decision in flight, and execute the next action."
MSG="$MSG Self-derive the continuation prompt from the summary; do not request clarification unless the summary is genuinely ambiguous about what was being worked on."
if [ -n "$SNAPSHOT" ]; then
    MSG="$MSG A pre-compact git/repo snapshot was captured at $SNAPSHOT — read it if you need branch, working-tree, or recent-commit state that the summary lost."
fi
MSG="$MSG Safety rail: if the next step is destructive or non-reversible (force-push, rm -rf, schema migration, sending external messages), confirm with the user first per the standard executing-actions-with-care rules. Everything else: proceed."

jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "PostCompact",
    additionalContext: $msg
  }
}'

exit 0
