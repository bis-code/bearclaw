#!/bin/sh
# memory-index-freshness.sh <index-name> <src-memory-dir> — rebuild if stale.
set +e
NAME="$1"; SRC="$2"; [ -d "$SRC" ] || exit 0
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"; mkdir -p "$STATE"
STAMP="$STATE/$NAME.built"
NEWEST=$(find "$SRC" -name '*.md' -type f -newer "$STAMP" 2>/dev/null | head -1)
if [ ! -f "$STAMP" ] || [ -n "$NEWEST" ]; then
  DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
  if [ -n "${MEMORY_BUILD_CMD+x}" ]; then
    $MEMORY_BUILD_CMD && touch "$STAMP"
  else
    sh "$DIR/lib/memory-index-build.sh" "$NAME" "$SRC" && touch "$STAMP"
  fi
fi
exit 0
