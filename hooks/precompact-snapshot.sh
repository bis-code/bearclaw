#!/bin/sh
# precompact-snapshot.sh — runs from PreCompact hook (user scope, all projects).
#
# Hooks cannot invoke slash commands like /handoff, so this captures a
# working-memory snapshot to ~/.claude/handoffs/precompact-<ts>.md right before
# context compaction discards the conversation. Captures:
#   1. git context (repo / branch / working tree / recent commits)
#   2. current TodoWrite todos      (last TodoWrite in the transcript)
#   3. recently-edited files        (find <cwd> -mmin -RECENT_MINS, noise filtered)
#   4. transcript tail              (last TAIL_MSGS user/assistant text exchanges)
#
# Reads the PreCompact stdin JSON for `.cwd` and `.transcript_path`.
# Always exits 0 — compaction must not be blocked by a snapshot failure.
# Read by future sessions to recover where the previous one left off.
#
# Env overrides (tests): RECENT_MINS (default 120), TAIL_MSGS (default 6),
#                        SNAPSHOT_DIR (default ~/.claude/handoffs)

set +e  # never propagate non-zero — a sub-command failure must not bubble up

RECENT_MINS="${RECENT_MINS:-120}"
TAIL_MSGS="${TAIL_MSGS:-6}"

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

# --- recently-edited files under CWD (noise filtered) ---
RECENT_FILES=$(find "$CWD" -type f -mmin "-$RECENT_MINS" 2>/dev/null \
    | grep -vE '/(\.git|node_modules|\.build|build|DerivedData|dist|\.next|target|\.venv|__pycache__)/' \
    | head -30)

# --- transcript tail: last TAIL_MSGS user/assistant text snippets ---
TAIL_TEXT=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TAIL_TEXT=$(jq -rs --argjson n "$TAIL_MSGS" '
        [ .[]
          | (.message.role // .type) as $role
          | .message.content? // empty
          | (if type=="array" then .[] else {type:"text", text:.} end)
          | select(.type=="text" and (.text // "") != "")
          | "**\($role):** \((.text | gsub("\\s+";" "))[0:280])" ]
        | .[-$n:] | .[]
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
    echo "## Recently edited (last ${RECENT_MINS} min)"
    echo ""
    echo '```'
    if [ -n "$RECENT_FILES" ]; then
        echo "$RECENT_FILES"
    else
        echo "(none)"
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
    echo "## Conversation tail (last ${TAIL_MSGS} text exchanges)"
    echo ""
    if [ -n "$TAIL_TEXT" ]; then
        echo "$TAIL_TEXT"
    else
        echo "_(no transcript text available)_"
    fi
    echo ""
    echo "---"
    echo ""
    echo "Auto-snapshot taken just before context compaction. For a full"
    echo "conversational handoff, run \`/handoff\` BEFORE the next compact."
} > "$OUT" 2>/dev/null

exit 0
