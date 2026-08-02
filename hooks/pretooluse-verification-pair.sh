#!/bin/sh
# pretooluse-verification-pair.sh — PreToolUse (Skill) pair enforcement.
# Mechanizes the execution-discipline rule: superpowers:verification-before-
# completion MUST run before superpowers:finishing-a-development-branch.
# Evidence: June 2026 audit — 2 verification runs vs 10 finishing runs (20%),
# unchanged from May despite the prose rule.
# SPEED BUMP, NOT WALL: finishing without verification is denied ONCE per
# session with the pair named; re-issuing the same call passes.
# Env seams (tests): CLAUDE_PAIR_STATE_DIR.

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Skill" ] || exit 0

SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
STATE_DIR="${CLAUDE_PAIR_STATE_DIR:-${TMPDIR:-/tmp}}"

case "$SKILL" in
  superpowers:verification-before-completion|verification-before-completion)
    # Verification invoked — record it for this session.
    : > "$STATE_DIR/claude-verify-ran-$SID" 2>/dev/null || true
    exit 0
    ;;
  superpowers:finishing-a-development-branch|finishing-a-development-branch)
    [ -f "$STATE_DIR/claude-verify-ran-$SID" ] && exit 0   # pair satisfied
    DENY_MARK="$STATE_DIR/claude-pair-denied-$SID"
    [ -f "$DENY_MARK" ] && exit 0                          # speed bump spent
    : > "$DENY_MARK" 2>/dev/null || true
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Required pair (rules/execution-discipline.md): invoke superpowers:verification-before-completion BEFORE finishing-a-development-branch — verify with evidence, then finish. If verification genuinely does not apply, re-issue this same call: this gate denies only once per session."}}'
    exit 0
    ;;
  *) exit 0 ;;
esac
