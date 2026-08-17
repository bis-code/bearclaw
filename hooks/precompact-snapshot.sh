#!/bin/sh
# precompact-snapshot.sh — runs from PreCompact hook (user scope, all projects).
#
# Captures a SLIM working-memory snapshot to ~/.claude/handoffs/precompact-<ts>.md
# right before context compaction: git context + current TodoWrite todos. The
# old full-tree `find -mmin` walk and transcript tail were dropped 2026-08-16
# (D4): native compaction summaries carry conversational continuity; this file
# only preserves the repo-state facts a summary tends to lose. Keeps the last
# 10 snapshots (older ones pruned here) so the dir stops accreting forever.
#
# Reads the PreCompact stdin JSON for `.cwd` and `.transcript_path`.
# Always exits 0 — compaction must not be blocked by a snapshot failure.
#
# Env overrides (tests): SNAPSHOT_DIR (default ~/.claude/handoffs),
#                        SNAPSHOT_KEEP (default 10)

set +e  # never propagate non-zero — a sub-command failure must not bubble up

INPUT=$(cat 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$(pwd)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="${SNAPSHOT_DIR:-$HOME/.claude/handoffs}"
OUT="$OUT_DIR/precompact-$TS.md"
mkdir -p "$OUT_DIR" 2>/dev/null

# --- git context (derived from CWD; empty fields when not in a repo) ---
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
SHORT_SHA=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
STATUS=$(git -C "$CWD" status --short 2>/dev/null | head -40)
LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null)

# --- current todos: last TodoWrite tool_use in the transcript ---
TODOS=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TODOS=$(jq -rs '
        [ .[] | .message.content? // empty
          | (if type=="array" then .[] else empty end)
          | select(.type=="tool_use" and .name=="TodoWrite") | .input.todos ]
        | last // empty
        | .[]? | "- [\(.status // "?")] \(.content // .activeForm // "")"
    ' "$TRANSCRIPT" 2>/dev/null)
fi

{
    echo "# Pre-compact auto-snapshot"
    echo ""
    echo "**Captured:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "**Working dir:** \`$CWD\`"
    if [ -n "$GIT_ROOT" ]; then
        echo "**Git repo:** \`$GIT_ROOT\`"
        echo "**Branch:** \`$BRANCH\` @ \`$SHORT_SHA\`"
    else
        echo "**Git repo:** (not in a git repo)"
    fi
    echo ""
    echo "## Current todos"
    echo ""
    if [ -n "$TODOS" ]; then
        echo "$TODOS"
    else
        echo "_(no TodoWrite todos found in the transcript)_"
    fi
    echo ""
    echo "## Working tree"
    echo ""
    echo '```'
    if [ -n "$STATUS" ]; then
        echo "$STATUS"
    else
        echo "(clean or no git repo)"
    fi
    echo '```'
    echo ""
    echo "## Last 5 commits"
    echo ""
    echo '```'
    if [ -n "$LOG" ]; then
        echo "$LOG"
    else
        echo "(no git history available)"
    fi
    echo '```'
    echo ""
    echo "---"
    echo ""
    echo "Auto-snapshot taken just before context compaction. For a full"
    echo "conversational handoff, run \`/handoff\` BEFORE the next compact."
} > "$OUT" 2>/dev/null

# --- prune: keep the newest SNAPSHOT_KEEP snapshots, delete the rest ---
KEEP="${SNAPSHOT_KEEP:-10}"
ls -1t "$OUT_DIR"/precompact-*.md 2>/dev/null | tail -n +"$((KEEP + 1))" | while IFS= read -r old; do
    rm -f "$old" 2>/dev/null
done

exit 0
