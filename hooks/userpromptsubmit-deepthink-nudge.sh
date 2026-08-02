#!/bin/sh
# userpromptsubmit-deepthink-nudge.sh — UserPromptSubmit nudge (advisory).
# When the prompt matches an architecture/design trigger (the tooling.md
# deep-think mandate surface), inject additionalContext reminding the model to
# call mcp__deep-think__think BEFORE reasoning solo. Fires at most ONCE per
# session (marker file) so it never nags.
# Why a hook: 30d of transcripts showed 0 deep-think calls despite the prose
# mandate — rules don't steer tool choice at decision time; prompt-time
# context injection does (verified vs code.claude.com/docs/en/hooks, 2026-06).
# Env seams (tests): CLAUDE_NUDGE_STATE_DIR (marker dir).

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)

[ -n "$PROMPT" ] || exit 0

# Only nudge toward a tool that can actually start. The MCP is optional; when
# its binary is absent the honest behaviour is silence, not a false claim that
# the tool is "immediately callable". Env seam for tests: DEEPTHINK_BIN.
DEEPTHINK_BIN="${DEEPTHINK_BIN:-mcp-deep-think}"
case "$DEEPTHINK_BIN" in
  */*) [ -x "$DEEPTHINK_BIN" ] || exit 0 ;;
  *)   command -v "$DEEPTHINK_BIN" >/dev/null 2>&1 || exit 0 ;;
esac

printf '%s' "$PROMPT" | grep -qiE 'architect|schema (design|change|migration)|data model|system design|api contract|auth flow|payment flow|multi-?module' || exit 0

STATE_DIR="${CLAUDE_NUDGE_STATE_DIR:-${TMPDIR:-/tmp}}"
MARK="$STATE_DIR/claude-deepthink-nudge-$SID"
[ -f "$MARK" ] && exit 0
: > "$MARK" 2>/dev/null || true

jq -n '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:"TOOL REMINDER (rules/tooling.md): this prompt matches an architecture/design trigger. Use mcp__deep-think__think to structure the key decision BEFORE proposing a design — record the trade-off as one or more thoughts. The tool is registered in .mcp.json and its binary is on PATH."}}'
exit 0
