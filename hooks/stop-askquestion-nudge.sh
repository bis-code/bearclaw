#!/bin/sh
# stop-askquestion-nudge.sh — Stop hook (user scope, all projects).
#
# Enforces the response-discipline rule "ask via selectable options, not prose":
# when Claude ends a turn with a discrete 2-4 way choice written as a prose list
# instead of calling the AskUserQuestion tool, block ONCE per session and tell it
# to re-ask via AskUserQuestion (selectable cards are easier to read + answer,
# especially on mobile). SPEED BUMP, NOT A WALL — after the first nudge per
# session the gate is silent, so a false positive costs at most one extra turn.
#
# Hooks can't force a tool call; the rule does the steering, this just catches
# lapses. Detection is deliberately conservative (needs an explicit options
# shape) to keep false nags rare.
#
# Always exits 0 on the allow path. Env seams (tests):
#   CLAUDE_ASKQ_STATE_DIR  — where the once-per-session marker lives.

set +e

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Avoid loops: if THIS Stop is already the result of a previous block, stand down.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

# Resolve transcript: prefer stdin, else search by session_id.
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    [ -n "$SID" ] && TRANSCRIPT=$(find "$HOME/.claude/projects" -maxdepth 3 -name "${SID}.jsonl" -type f 2>/dev/null | head -1)
fi
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# Last assistant message's concatenated text blocks (from the transcript tail,
# 256KB cap, so the Stop hook stays cheap). fromjson? tolerates a truncated
# leading line. tool_use blocks (incl. AskUserQuestion) carry no .text, so a turn
# that DID ask via the tool yields no prose here -> no false nudge.
LAST=$(tail -c 262144 "$TRANSCRIPT" 2>/dev/null | jq -rRs '
  [split("\n")[] | fromjson?
   | select(.type == "assistant")
   | .message.content? // [] | (if type=="array" then . else [] end)
   | map(select(.type=="text") | .text) | join("\n")]
  | map(select(. != "")) | last // ""' 2>/dev/null)
[ -n "$LAST" ] || exit 0

# Conservative options-question detection. Fire only on an explicit shape:
#   (a) "Option A"/"Option B" appearing twice, OR
#   (b) an inline lettered pair "a) ... b)", OR
#   (c) >=2 enumerated lines (1) / 1.) AND a question mark AND a choice cue.
is_options=0
# grep -o then wc: count OCCURRENCES, not matching lines (the prose is often a
# single line, so "Option A ... Option B" must be counted as two, not one).
opt_count=$(printf '%s' "$LAST" | grep -oiE '(^|[^a-z])option [a-d]([^a-z]|$)' | wc -l | tr -d ' ')
[ "${opt_count:-0}" -ge 2 ] && is_options=1
if [ "$is_options" -eq 0 ]; then
    printf '%s' "$LAST" | grep -qiE '(^|[^a-z])a\)[^?]*[^a-z]b\)' && is_options=1
fi
if [ "$is_options" -eq 0 ]; then
    enum=$(printf '%s' "$LAST" | grep -cE '^[[:space:]]*[0-9][.)][[:space:]]')
    if [ "${enum:-0}" -ge 2 ] && printf '%s' "$LAST" | grep -q '?' \
       && printf '%s' "$LAST" | grep -qiE 'which|prefer|should i|do you want|want me to|pick (one|either)|choose|go with|option'; then
        is_options=1
    fi
fi
[ "$is_options" -eq 1 ] || exit 0

# Once per session: only the first lapse is blocked; re-stop passes.
STATE_DIR="${CLAUDE_ASKQ_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE_KEY="${SID:-$(printf '%s' "$TRANSCRIPT" | shasum 2>/dev/null | cut -c1-12)}"
MARK="$STATE_DIR/askq-nudged-${STATE_KEY}"
[ -f "$MARK" ] && exit 0
: > "$MARK" 2>/dev/null || true

jq -n '{
  decision: "block",
  reason: "That reply offers the user a discrete set of options as prose. Per rules/response-discipline.md (ask via selectable options), re-ask that choice using the AskUserQuestion tool so the options render as selectable cards — easier to read and answer, especially on mobile. Keep any necessary prose context, but move the actual choice into AskUserQuestion. (This nudge fires once per session.)"
}'
exit 0
