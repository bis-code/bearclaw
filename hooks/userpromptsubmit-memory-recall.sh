#!/bin/sh
# userpromptsubmit-memory-recall.sh — inject relevant memory, gated.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
# Guard the dot-source: a failed source aborts the whole script under dash even
# with set +e, which would emit a stderr error + non-zero exit on every prompt.
[ -f "$DIR/lib/memory-store.sh" ] && . "$DIR/lib/memory-store.sh"
# MEMBACKEND_LIB_DIR: this script lives in hooks/, not hooks/lib/, so
# memory-backend.sh's own $0-based colocation lookup (documented in its
# header) would resolve to the wrong directory — point it at hooks/lib/
# explicitly, same seam it names for "future callers elsewhere".
if [ -f "$DIR/lib/memory-backend.sh" ]; then
  MEMBACKEND_LIB_DIR="$DIR/lib"
  . "$DIR/lib/memory-backend.sh"
fi
# One definition of where memory lives, shared with SessionStart, Stop and
# bin/claude-memory-recall — see hooks/lib/memory-roots.sh for why.
[ -f "$DIR/lib/memory-roots.sh" ] && . "$DIR/lib/memory-roots.sh"
# Transcript history, as a tier that fires only on a question about the past.
[ -f "$DIR/lib/episodic-recall.sh" ] && . "$DIR/lib/episodic-recall.sh"
INPUT=$(cat 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0
# skip trivial
words=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
case "$PROMPT" in y|yes|no|ok|continue|/*) exit 0 ;; esac
[ "$words" -ge 4 ] || exit 0

# Each tier prefers the opt-in memory-backend adapter (local-embed); "none" by
# default falls straight through to bearclaw's own leann index, so an install
# that already has leann keeps its existing recall unchanged. The adapter's
# JSONL {"score","path","snippet"} needs reshaping into the {"score","text",
# "metadata":{file_name}} array memory-recall.py expects; leann's own
# `--json --show-metadata` output is already in that shape, so the fallback
# passes straight through (as before this backend existed).
#
# Every root is searched now. The gate that used to sit here served only the
# global index, because the adapter's first scope was a single corpus over
# memory-global — which meant every curated per-repo memory was indexed by
# nothing and reachable by nothing. Indexes are keyed per tier now, so each
# name addresses its own vectors and this can simply dispatch.
search() { # <index-name> <corpus-dir>
  # Fetch wider than we inject. The backend returns one chunk per (file, entry),
  # so a wider fetch buys distinct candidates for the formatter to rank rather
  # than more windows of the same file — at 8 the list could be spent before a
  # relevant file appeared. The injected count is still governed by MEMORY_TOP_K
  # and the token budget, so this costs a little cosine arithmetic over an
  # in-memory index, not a wider injection.
  # stderr is discarded, and that is a deliberate hot-path decision, not
  # sloppiness. A tier whose index has not been built yet makes the backend
  # print a diagnostic ("no index at ... run build first") — once per prompt,
  # per unbuilt tier, forever. Before every root was searched there was only
  # the global tier and it was always built, so this never fired; now every
  # repo produces one until its first rebuild lands. The prompt cannot act on
  # it either way: a backend that errors and a backend with no hits are the
  # same event here, and both must fail open. The diagnostic still reaches a
  # person where they asked for it — SessionStart's "backend not ready" note,
  # and scripts/memory-doctor.sh.
  _sr=$(membackend_search "$1" "$PROMPT" 20 "$2" 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$_sr" ]; then
    printf '%s\n' "$_sr" | jq -s '[.[] | {score: .score, text: .snippet, metadata: {file_name: (.path | split("/") | last)}}]' 2>/dev/null
    return
  fi
  leann search "$1" "$PROMPT" --top-k 20 --json --non-interactive --show-metadata 2>/dev/null
}

PARTS=$(mktemp 2>/dev/null) || PARTS=""
# Root dirs are collected as positional params rather than a string. A repo path
# containing a space would split into two broken --mem-dir values otherwise, and
# the formatter would silently lose the flags for that tier.
set --
if [ -n "${MEMORY_SEARCH_CMD:-}" ]; then
  # Test seam: the stub stands in for the whole tier sweep, called once. Calling
  # it per root would inject N copies of one canned answer and prove nothing.
  _stub=$(eval "$MEMORY_SEARCH_CMD")
  [ -n "$PARTS" ] && printf '%s\n' "$_stub" >> "$PARTS"
fi
# memroots_emit prints one "<index-name><TAB><dir>" line per root that EXISTS,
# so a repo with no memory of its own contributes nothing rather than a miss.
# The corpus dir is passed to search as well as to the formatter: it makes the
# backend refuse an index built from a different directory, which is what keeps
# two same-basename repos from answering each other's questions.
while IFS="	" read -r _idx _dir; do
  [ -n "$_idx" ] || continue
  set -- "$@" --mem-dir "$_dir"
  [ -n "${MEMORY_SEARCH_CMD:-}" ] && continue
  _part=$(search "$_idx" "$_dir")
  [ -n "$_part" ] && [ -n "$PARTS" ] && printf '%s\n' "$_part" >> "$PARTS"
done <<EOF
$(memroots_emit "$CWD")
EOF
MERGED=$(jq -s 'add // []' < "${PARTS:-/dev/null}" 2>/dev/null)
[ -n "$PARTS" ] && rm -f "$PARTS"
[ -n "$MERGED" ] || exit 0
# Run the formatter; capture the <memory-context> block on stdout and the chosen
# entry-ids on fd 3 (the formatter emits one id per line there). The usage log
# feeds Phase-2 frequency/recency scoring back into the formatter on later turns.
IDS_FILE=$(mktemp 2>/dev/null) || IDS_FILE=""
BLOCK=$(printf '%s' "$MERGED" \
  | MEMORY_USAGE_LOG="$MEMSTORE_USAGE/recall-log.jsonl" \
    python3 "$DIR/lib/memory-recall.py" --floor "${MEMORY_FLOOR:-0.5}" \
      --top-k "${MEMORY_TOP_K:-4}" --budget-tokens "${MEMORY_BUDGET_TOKENS:-225}" \
      "$@" \
    3>"${IDS_FILE:-/dev/null}" 2>/dev/null)
# Transcript history. Runs only when the prompt asks about what happened before,
# so it costs nothing on an ordinary turn — see hooks/lib/episodic-recall.sh for
# why the trigger is intent rather than "curated recall found nothing" (measured:
# curated recall found something on 40 of 40 eval prompts, so a score-based
# trigger would never have fired at all).
EPISODIC=""
if command -v episodic_recall_block >/dev/null 2>&1; then
  EPISODIC=$(episodic_recall_block "$PROMPT" 2 2>/dev/null)
fi

if [ -z "$BLOCK" ] && [ -z "$EPISODIC" ]; then
  [ -n "$IDS_FILE" ] && rm -f "$IDS_FILE"
  exit 0
fi
# Kept as separate blocks on purpose: a curated memory was written down
# deliberately, a transcript line is only something that was once said. Merging
# them would launder the second into the authority of the first.
if [ -n "$EPISODIC" ]; then
  if [ -n "$BLOCK" ]; then
    BLOCK="$BLOCK
$EPISODIC"
  else
    BLOCK="$EPISODIC"
  fi
fi
# Log surfaced ids (best-effort; never blocks the prompt).
if [ -n "$IDS_FILE" ] && [ -s "$IDS_FILE" ]; then
  IDS_JSON=$(jq -R -s -c 'split("\n") | map(select(length>0))' < "$IDS_FILE" 2>/dev/null)
  if [ -n "$IDS_JSON" ] && [ "$IDS_JSON" != "[]" ]; then
    LINE=$(jq -nc --argjson ts "$(date +%s)" --argjson ids "$IDS_JSON" '{ts:$ts, ids:$ids}' 2>/dev/null)
    [ -n "$LINE" ] && memstore_append_usage recall-log.jsonl "$LINE"
  fi
fi
[ -n "$IDS_FILE" ] && rm -f "$IDS_FILE"
jq -n --arg c "$BLOCK" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
exit 0
