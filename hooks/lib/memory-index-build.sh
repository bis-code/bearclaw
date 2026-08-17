#!/bin/sh
# memory-index-build.sh <index-name> <src-memory-dir>
# Exit: 0 built · 2 bad args · 3 leann missing · 4 empty corpus · 5 build failed
# Build output -> $STATE/<name>.build.log; failure marker -> $STATE/<name>.build.err
# (cleared on success). Callers gate stamping on exit 0; sessionstart surfaces .err.
set -e
NAME="${1:-}"; SRC="${2:-}"
if [ -z "$NAME" ] || [ -z "$SRC" ]; then
  echo "usage: memory-index-build.sh <index-name> <src-memory-dir>" >&2
  exit 2
fi
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"
mkdir -p "$STATE"
LOG="$STATE/$NAME.build.log"; ERRMARK="$STATE/$NAME.build.err"

if ! command -v leann >/dev/null 2>&1; then
  { echo "leann not installed — memory index '$NAME' not built."
    echo "recipe: memory-global/ERRORS.md (2026-06-15 leann reinstall; 2026-08-16 Linux/CPU notes)"
  } > "$ERRMARK"
  echo "memory-index-build: leann not installed (index '$NAME' skipped)" >&2
  exit 3
fi

STAGE="${TMPDIR:-/tmp}/${NAME}-stage"
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
sh "$DIR/memory-corpus-stage.sh" "$SRC" "$STAGE"
if [ -z "$(ls -A "$STAGE" 2>/dev/null)" ]; then
  rm -f "$ERRMARK"
  exit 4   # empty corpus — nothing to build; no stamp so a future corpus retries
fi

if ( cd "$HOME" && leann build "$NAME" --docs "$STAGE" --file-types .md \
    --doc-chunk-size 512 --doc-chunk-overlap 64 --force ) >"$LOG" 2>&1; then
  rm -f "$ERRMARK"
else
  { echo "leann build failed for '$NAME' — last 20 log lines (full: $LOG):"
    tail -20 "$LOG"
  } > "$ERRMARK"
  tail -5 "$LOG" >&2
  exit 5
fi
