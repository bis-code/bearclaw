#!/bin/sh
# memory-prune.sh <memory-dir> [days] — decay REVIEW list (NEVER deletes).
# Flags entries not recalled within <days> (default MEMORY_PRUNE_DAYS=90), using
# the usage log's last-recall timestamp per id (id = filename stem). Output is a
# review list for a human to act on — pruning stays a deliberate manual step.
set +e
MEM="$1"; DAYS="${2:-${MEMORY_PRUNE_DAYS:-90}}"
case "$DAYS" in
  ''|*[!0-9]*) printf 'memory-prune: invalid DAYS value "%s" — must be a positive integer\n' "$DAYS" >&2; exit 0 ;;
esac
[ "$DAYS" -gt 0 ] 2>/dev/null || { printf 'memory-prune: DAYS must be > 0, got "%s"\n' "$DAYS" >&2; exit 0; }
[ -d "$MEM" ] || exit 0
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$DIR/memory-store.sh"

LOG="$MEMSTORE_USAGE/recall-log.jsonl"

# Early exit: if usage log is absent or empty, nothing to flag yet.
if [ ! -s "$LOG" ]; then
  printf 'memory-prune: no recall history yet — nothing to flag\n' >&2
  exit 0
fi

NOW=$(date +%s)
CUTOFF=$((NOW - DAYS * 86400))

# Build "id<TAB>last_ts" map from the usage log (max ts per id).
last_ts_for() { # <id> -> epoch or empty
  [ -f "$LOG" ] || return 0
  jq -r --arg id "$1" '
    select(.ids // [] | index($id)) | .ts // 0
  ' "$LOG" 2>/dev/null | sort -n | tail -1
}

for f in "$MEM"/*.md; do
  [ -f "$f" ] || continue
  base=${f##*/}
  case "$base" in
    ERRORS*.md|MEMORY.md|README.md) continue ;;
  esac
  slug=${base%.md}
  LAST=$(last_ts_for "$slug")
  if [ -z "$LAST" ] || [ "$LAST" = "null" ]; then
    printf '%s\tNEVER\n' "$slug"
  elif [ "$LAST" -lt "$CUTOFF" ]; then
    printf '%s\t%s\n' "$slug" "$LAST"
  fi
done
exit 0
