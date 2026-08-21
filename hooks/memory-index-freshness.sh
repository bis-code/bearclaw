#!/bin/sh
# memory-index-freshness.sh <index-name> <src-memory-dir> — rebuild if stale.
# Concurrency: an mkdir lock (auto-broken after 30 min if a builder crashed)
# stops SessionStart and Stop firing overlapping builds against the shared
# stage dir — overlap could index a truncated corpus. The stamp carries the
# build-START time (mv'd into place on success) so edits made DURING a long
# build still re-trigger the next freshness check.
set +e
NAME="$1"; SRC="$2"; [ -d "$SRC" ] || exit 0
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"; mkdir -p "$STATE"
STAMP="$STATE/$NAME.built"
LOCK="$STATE/$NAME.lock"
# -L is load-bearing: $SRC is normally a SYMLINK (install.sh points the config
# root's memory-global at this repo). find does not follow a symlinked STARTING
# POINT without it, so this matched nothing on every machine and the index
# silently never rebuilt. The `[ -d "$SRC" ]` guard above does NOT catch it —
# -d follows symlinks, so the guard passes and only the traversal is blind.
# Measured 2026-08-20: 0 files matched without -L, 34 with it, 19 of them newer
# than a stamp 19 days old.
NEWEST=$(find -L "$SRC" -name '*.md' -type f -newer "$STAMP" 2>/dev/null | head -1)
if [ ! -f "$STAMP" ] || [ -n "$NEWEST" ]; then
  if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null   # stale lock from a crashed builder
  fi
  mkdir "$LOCK" 2>/dev/null || exit 0   # another build in flight — skip cleanly
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
  touch "$STAMP.start"
  DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
  if [ -n "${MEMORY_BUILD_CMD+x}" ]; then
    $MEMORY_BUILD_CMD && mv "$STAMP.start" "$STAMP"
  else
    sh "$DIR/lib/memory-index-build.sh" "$NAME" "$SRC" && mv "$STAMP.start" "$STAMP"
  fi
  rm -f "$STAMP.start"
fi
exit 0
