#!/bin/sh
# memory-migrate.sh — onboard the CURRENT project into semantic memory recall.
#
# No flags, one job. Run inside any project (exposed as `claude-memory-migrate`):
#   1. resolve the MAIN worktree (so a linked worktree onboards its parent repo,
#      not itself) — the same resolution sessionstart-load-memory.sh uses.
#   2. copy any LEGACY ~/.claude/projects/<encoded-root>/memory/*.md entries that
#      are NOT already in <repo>/.claude/memory/ into it. Purely additive:
#      existing canonical entries are never overwritten, and legacy is never
#      deleted (clean it up yourself once you trust the result).
#   3. build/refresh the <repo>-memory leann index from canonical memory.
#   4. print a one-line summary.
#
# Env seam (tests): MEMORY_BUILD_CMD overrides the index build.
set -e

CWD=$(pwd)
ROOT="$CWD"
GIT_COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$GIT_COMMON" ]; then
  ROOT=$(dirname "$GIT_COMMON")
fi
NAME=$(basename "$ROOT")
MEM_DIR="$ROOT/.claude/memory"
ENCODED=$(printf '%s' "$ROOT" | sed 's:/:-:g')
LEGACY="$HOME/.claude/projects/$ENCODED/memory"

mkdir -p "$MEM_DIR"

moved=0
skipped=0
if [ -d "$LEGACY" ]; then
  for f in "$LEGACY"/*.md; do
    [ -f "$f" ] || continue
    b=${f##*/}
    if [ -e "$MEM_DIR/$b" ]; then
      skipped=$((skipped + 1))            # already present — keep canonical, never clobber
    else
      cp "$f" "$MEM_DIR/$b"               # additive: legacy left intact
      moved=$((moved + 1))
    fi
  done
fi

DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
BUILT=skipped
if ls "$MEM_DIR"/*.md >/dev/null 2>&1; then
  if [ -n "${MEMORY_BUILD_CMD+x}" ]; then
    if sh -c "$MEMORY_BUILD_CMD" >/dev/null 2>&1; then BUILT=yes; else BUILT=failed; fi
  else
    if sh "$DIR/memory-index-build.sh" "${NAME}-memory" "$MEM_DIR" >/dev/null 2>&1; then BUILT=yes; else BUILT=failed; fi
  fi
fi

printf 'claude-memory-migrate: %s — moved %d new, skipped %d existing; index %s-memory build=%s\n' \
  "$NAME" "$moved" "$skipped" "$NAME" "$BUILT"
if [ -d "$LEGACY" ]; then
  printf '  legacy (left intact, clean up when ready): %s\n' "$LEGACY"
fi
