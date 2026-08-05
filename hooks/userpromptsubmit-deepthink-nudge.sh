#!/bin/sh
# userpromptsubmit-deepthink-nudge.sh — UserPromptSubmit nudge (advisory).
# When the prompt matches an architecture/design trigger (the tooling.md
# deep-think mandate surface), inject additionalContext reminding the model to
# call the deep-think plugin's think tool BEFORE reasoning solo. Fires at most
# ONCE per session (marker file) so it never nags.
# Why a hook: 30d of transcripts showed 0 deep-think calls despite the prose
# mandate — rules don't steer tool choice at decision time; prompt-time
# context injection does (verified vs code.claude.com/docs/en/hooks, 2026-06).
# Env seams (tests): CLAUDE_NUDGE_STATE_DIR (marker dir).

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)

[ -n "$PROMPT" ] || exit 0

# Only nudge toward a tool that can actually start. deep-think ships as a
# Claude Code plugin (deep-think@bis-code, no more PATH binary); the honest
# behaviour when it's not installed is silence, not a false claim that the
# tool is "immediately callable". Env seam for tests: DEEPTHINK_PLUGINS_FILE.
PLUGINS_FILE="${DEEPTHINK_PLUGINS_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json}"
[ -f "$PLUGINS_FILE" ] || exit 0
grep -q 'deep-think@bis-code' "$PLUGINS_FILE" 2>/dev/null || exit 0

printf '%s' "$PROMPT" | grep -qiE 'architect|schema (design|change|migration)|data model|system design|api contract|auth flow|payment flow|multi-?module' || exit 0

STATE_DIR="${CLAUDE_NUDGE_STATE_DIR:-${TMPDIR:-/tmp}}"
MARK="$STATE_DIR/claude-deepthink-nudge-$SID"
[ -f "$MARK" ] && exit 0
: > "$MARK" 2>/dev/null || true

jq -n '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:"TOOL REMINDER (rules/tooling.md): this prompt matches an architecture/design trigger. Use mcp__plugin_deep-think_deep-think__think to structure the key decision BEFORE proposing a design — record the trade-off as one or more thoughts. The deep-think plugin (deep-think@bis-code) is installed — call its think tool."}}'
exit 0
