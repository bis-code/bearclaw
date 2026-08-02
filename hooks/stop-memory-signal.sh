#!/bin/sh
# stop-memory-signal.sh — Stop hook. Heuristic (NO LLM) high-signal detector:
# regex the last user+assistant exchange and drop a marker into the per-session
# signal file. The memory-capture skill later prioritises these turns when it
# distills. Cheap between-prompt awareness without between-prompt LLM cost.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
[ -f "$DIR/lib/memory-store.sh" ] && . "$DIR/lib/memory-store.sh"

INPUT=$(cat 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$SID" ] || exit 0
[ -n "$TP" ] && [ -f "$TP" ] || exit 0

# Pull the last user text and last assistant text from the JSONL transcript.
# .message.content may be a string or an array of content blocks → coalesce text.
# Bound scan to last 100 lines to avoid O(transcript_size) cost on every Stop.
LAST_USER=$(tail -n 100 "$TP" 2>/dev/null | jq -rs '
  [ .[] | select(.message.role=="user") ] | last
  | (.message.content // "")
  | if type=="array" then (map(.text? // "") | join(" ")) else . end
' 2>/dev/null)
LAST_ASST=$(tail -n 100 "$TP" 2>/dev/null | jq -rs '
  [ .[] | select(.message.role=="assistant") ] | last
  | (.message.content // "")
  | if type=="array" then (map(.text? // "") | join(" ")) else . end
' 2>/dev/null)

NOW=$(date +%s)

emit() { # <kind> <snippet>
  _snip=$(printf '%s' "$2" | cut -b1-200)
  _json=$(jq -nc --argjson ts "$NOW" --arg kind "$1" --arg snippet "$_snip" \
    '{ts:$ts, kind:$kind, snippet:$snippet}' 2>/dev/null)
  [ -n "$_json" ] && memstore_append_signal "$SID" "$_json"
}

# correction / praise come from the USER turn
if printf '%s' "$LAST_USER" | grep -Eiq "no,? actually|that's wrong|not quite|actually,? i meant|incorrect"; then
  emit correction "$LAST_USER"
elif printf '%s' "$LAST_USER" | grep -Eiq "that worked|got it|perfect|nice|thanks,? that"; then
  emit praise "$LAST_USER"
fi
# resolution comes from the ASSISTANT turn
if printf '%s' "$LAST_ASST" | grep -Eiq "all tests pass|works now|fixed it|issue resolved|that fixed"; then
  emit resolved "$LAST_ASST"
fi

exit 0
