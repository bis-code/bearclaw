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
#
# Tool results are also recorded with role=="user" — they are the harness
# talking, not the human. Filtering them out is load-bearing: CLI stderr
# ("Incorrect store password") was being banked as a user correction.
LAST_USER=$(tail -n 100 "$TP" 2>/dev/null | jq -rs '
  [ .[]
    | select(.message.role=="user")
    | select(.toolUseResult == null)
    | select(.isMeta != true)
  ] | last
  | (.message.content // "")
  | if type=="array" then (map(select(.type=="text") | .text? // "") | join(" ")) else . end
' 2>/dev/null)
LAST_ASST=$(tail -n 100 "$TP" 2>/dev/null | jq -rs '
  [ .[] | select(.message.role=="assistant") ] | last
  | (.message.content // "")
  | if type=="array" then (map(select(.type=="text") | .text? // "") | join(" ")) else . end
' 2>/dev/null)

# The harness appends <system-reminder> blocks to the user turn. Their text is
# not what the user typed, so a trigger word inside one is not a reaction.
LAST_USER=$(printf '%s\n' "$LAST_USER" \
  | awk '/<system-reminder>/{s=1} !s{print} /<\/system-reminder>/{s=0}')

NOW=$(date +%s)

emit() { # <kind> <snippet>
  _snip=$(printf '%s' "$2" | cut -b1-200)
  _json=$(jq -nc --argjson ts "$NOW" --arg kind "$1" --arg snippet "$_snip" \
    '{ts:$ts, kind:$kind, snippet:$snippet}' 2>/dev/null)
  [ -n "$_json" ] && memstore_append_signal "$SID" "$_json"
}

# Snippet = a window AROUND the match, so a marker can be audited later.
# Recording the head of the turn made every marker unreadable: the reviewer saw
# 200 chars of preamble and no way to tell what fired it. Taking the matched
# *line* is not enough either — a turn is often one long unwrapped line.
# Empty output means no match; the caller tests for it.
match_snippet() { # <text> <pattern>
  printf '%s\n' "$1" | awk -v pat="$2" '
    match(tolower($0), pat) {
      start = RSTART - 60; if (start < 1) start = 1
      print substr($0, start, 200); exit
    }'
}

# A reaction IS the opening of the turn ("no, actually…", "perfect, now do X").
# Anything looser drowns in pasted content: matching the whole turn banked a
# stray "Nice" 9k chars into a prompt, and even a 400-byte window still matched
# "[S153] Nice." inside pasted video dialogue. So: the first non-empty line
# only, anchored at its start. This trades recall for precision deliberately —
# a mid-turn correction is missed, but 5 of 5 markers in a 22-session queue were
# false, and a marker stream that is pure noise is worse than none.
USER_LEAD=$(printf '%s\n' "$LAST_USER" | awk 'NF {print; exit}' | cut -b1-200)

# POSIX ERE only — no \b, \d, or other GNU extensions. Backslashes are doubly
# unsafe here: `awk -v` expands escape sequences before awk ever sees the
# pattern, so a "\b" word boundary silently becomes a literal backspace and the
# rule matches nothing. Use ([^a-z]|$) as the word-end guard instead.
CORRECTION="^[[:punct:][:space:]]*(no,? actually|that.?s wrong|not quite|actually,? i meant|that.?s incorrect|that is incorrect)"
PRAISE="^[[:punct:][:space:]]*(that worked|got it|perfect|nice|thanks,? that)([^a-z]|$)"
RESOLVED="all tests pass|works now|fixed it|issue resolved|that fixed"

# correction / praise come from the USER turn
if m=$(match_snippet "$USER_LEAD" "$CORRECTION") && [ -n "$m" ]; then
  emit correction "$m"
elif m=$(match_snippet "$USER_LEAD" "$PRAISE") && [ -n "$m" ]; then
  emit praise "$m"
fi
# resolution comes from the ASSISTANT turn — it lands at the end of a long turn,
# so this one is not lead-anchored; the match window keeps it auditable.
if m=$(match_snippet "$LAST_ASST" "$RESOLVED") && [ -n "$m" ]; then
  emit resolved "$m"
fi

exit 0
