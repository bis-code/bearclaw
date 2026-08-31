#!/bin/sh
# hooks/lib/membackend-local-embed.sh — local-embed memory-backend CLI (T15).
#
# Replaces cognee (stub, ~100s/query when measured — disqualified) AND leann
# (retired) for live per-prompt recall: a small fastembed index over
# memory-global/*.md, run through the venv install.sh creates guardedly at
# $MEMORY_VENV (default ~/.claude/memory-venv). Every path that can't serve
# exits 3 (fallback) — never hangs, never exit 1 into a hook.
#
# Usage (CLI surface hooks/lib/memory-backend.sh dispatches to):
#   membackend-local-embed.sh search <corpus-name> <query> <top-k>
#   membackend-local-embed.sh dedup  <corpus-name> <candidate-file>
#   membackend-local-embed.sh health
#
# v1 scope: a single global index (memory-global/*.md) — <corpus-name> is
# accepted for T7 contract-compatibility but not routed on; there is only one
# corpus to search in this task's scope. search/dedup exit 3 identically
# when the venv, fastembed, or the index itself is missing.
set +e

DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
VENV="${MEMORY_VENV:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-venv}"
PY="$VENV/bin/python3"
SCRIPT="$DIR/local-embed.py"
IDX="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory/local-embed-index.json"

_health() {
  if [ ! -x "$PY" ]; then
    echo "local-embed: venv python not found at $PY (run install.sh)" >&2
    return 3
  fi
  if ! "$PY" -c 'import fastembed' >/dev/null 2>&1; then
    echo "local-embed: fastembed not importable in $VENV" >&2
    return 3
  fi
  if [ ! -f "$IDX" ]; then
    echo "local-embed: no index at $IDX (run: local-embed.py build)" >&2
    return 3
  fi
  return 0
}

case "$1" in
  health)
    _health
    exit $?
    ;;
  search)
    # $2=corpus (unused, v1 single-corpus) $3=query $4=top-k
    QUERY="$3"; TOPK="${4:-5}"
    if [ ! -x "$PY" ]; then
      echo "local-embed: venv python not found at $PY (run install.sh)" >&2
      exit 3
    fi
    "$PY" "$SCRIPT" search "$QUERY" --top-k "$TOPK"
    exit $?
    ;;
  dedup)
    # $2=corpus (unused) $3=candidate-file — embed the candidate's text and
    # return the nearest existing chunk(s); the memory-dedup consumer decides
    # NEW vs SKIP from the score, same as it does for every other backend.
    CAND_FILE="$3"
    if [ ! -x "$PY" ]; then
      echo "local-embed: venv python not found at $PY (run install.sh)" >&2
      exit 3
    fi
    if [ ! -f "$CAND_FILE" ]; then
      echo "local-embed: candidate file not found: $CAND_FILE" >&2
      exit 1
    fi
    CAND_TEXT=$(cat "$CAND_FILE")
    "$PY" "$SCRIPT" search "$CAND_TEXT" --top-k 5
    exit $?
    ;;
  *)
    echo "usage: membackend-local-embed.sh search|dedup|health ..." >&2
    exit 1
    ;;
esac
