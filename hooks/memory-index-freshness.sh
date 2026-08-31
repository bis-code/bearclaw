#!/bin/sh
# memory-index-freshness.sh <index-name> <src-memory-dir> — rebuild if stale.
# Concurrency, two locks, both mkdir-based and auto-broken after 30 min if a
# builder crashed: a per-corpus one so SessionStart and Stop cannot fire
# overlapping builds of the same index, and a machine-wide one capping the whole
# machine at one build (see GLOCK below for why). The stamp carries the
# build-START time (mv'd into place on success) so edits made DURING a long
# build still re-trigger the next freshness check.
set +e
NAME="$1"; SRC="$2"; [ -d "$SRC" ] || exit 0
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"; mkdir -p "$STATE"
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)

# This script lives in hooks/, not hooks/lib/, so memory-backend.sh's own
# $0-based colocation lookup would resolve to hooks/ and find no backend —
# every dispatch would return 3 and the build would silently no-op. Same seam
# the other hooks outside lib/ use. (${...:-} keeps the test override working.)
MEMBACKEND_LIB_DIR="${MEMBACKEND_LIB_DIR:-$DIR/lib}"
. "$DIR/lib/memory-backend.sh"
BACKEND=$(membackend_name)

# The stamp is namespaced by BACKEND. It records "this backend has indexed this
# corpus", and switching engines leaves the previous one's stamps on disk with no
# index behind them. An un-namespaced stamp lets a new backend inherit the old
# one's claim and never build at all.
STAMP="$STATE/$NAME.$BACKEND.built"
LOCK="$STATE/$NAME.lock"
# Machine-wide, backend-agnostic: one index build at a time. Not about corpus
# corruption — indexes are per-tier, so two tiers cannot overwrite each other. It
# is about cost. Embedding a corpus saturates several cores for tens of seconds;
# every repo tier waking at once would take the machine down. A skipped build is
# free to retry, because its stamp was never written.
GLOCK="$STATE/build.lock"

# Retire this corpus's pre-namespacing stamp once. Narrow on purpose: only the
# exact file this script would itself have written under the old scheme, never a
# sweep.
[ -f "$STATE/$NAME.built" ] && rm -f "$STATE/$NAME.built"
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

  if [ -d "$GLOCK" ] && [ -n "$(find "$GLOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
    rmdir "$GLOCK" 2>/dev/null   # stale global lock from a crashed builder
  fi
  # Some other corpus is building. Exit 0 and leave the stamp unwritten so the
  # next SessionStart picks this corpus up; the EXIT trap frees our own lock.
  mkdir "$GLOCK" 2>/dev/null || exit 0
  trap 'rmdir "$GLOCK" 2>/dev/null; rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

  touch "$STAMP.start"
  if [ -n "${MEMORY_BUILD_CMD+x}" ]; then
    $MEMORY_BUILD_CMD && mv "$STAMP.start" "$STAMP"
  else
    # Prefer the configured pluggable backend's own build. It returns 3 when no
    # backend is configured, which is the default here — and that is the case the
    # standalone index builder still covers, so the two paths are tried in order
    # rather than one replacing the other.
    membackend_build "$NAME" "$SRC"
    _mif_rc=$?
    if [ "$_mif_rc" -eq 0 ]; then
      mv "$STAMP.start" "$STAMP"
    elif [ -f "$DIR/lib/memory-index-build.sh" ]; then
      sh "$DIR/lib/memory-index-build.sh" "$NAME" "$SRC" && mv "$STAMP.start" "$STAMP"
    fi
  fi
  rm -f "$STAMP.start"
fi
exit 0
