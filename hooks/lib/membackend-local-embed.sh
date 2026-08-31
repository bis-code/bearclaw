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
#   membackend-local-embed.sh search <corpus-name> <query> <top-k> [<corpus-dir>]
#   membackend-local-embed.sh dedup  <corpus-name> <candidate-file>
#   membackend-local-embed.sh build  <corpus-name> <corpus-dir>
#   membackend-local-embed.sh health [<corpus-name>]
#
# <corpus-name> IS routed on now: it selects the per-tier index
# local-embed-<corpus-name>.json, so the global tier and each repo tier keep
# separate vectors. Before this, every name resolved to one shared index file,
# which meant whichever tier built last silently replaced the other's vectors
# and searches answered from the wrong corpus while reporting healthy.
# health takes the same name, because "is the backend up" is not a useful
# question when there are several indexes: a repo whose index has never been
# built is unhealthy for that repo and fine for the global tier.
# search/dedup/health exit 3 identically when the venv, fastembed, or the index
# for the requested tier is missing.
set +e

DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
VENV="${MEMORY_VENV:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-venv}"
PY="$VENV/bin/python3"
SCRIPT="$DIR/local-embed.py"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"

# The index key is the corpus name, reduced to filename-safe characters — the
# same reduction local-embed.py applies, so both sides agree on the path.
_key_for() {
  printf '%s' "${1:-global}" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^[-.]*//; s/[-.]*$//'
}

_idx_for() {
  _k=$(_key_for "$1")
  [ -n "$_k" ] || _k=global
  printf '%s/local-embed-%s.json' "$STATE_DIR" "$_k"
}

_health() { # $1 = corpus name (optional; defaults to the global tier)
  IDX=$(_idx_for "${1:-global}")
  if [ ! -x "$PY" ]; then
    echo "local-embed: venv python not found at $PY (run install.sh)" >&2
    return 3
  fi
  # fastembed presence is checked ON DISK, not by importing it: `python -c
  # "import fastembed"` costs ~0.27s and this gate runs at every SessionStart.
  # The check stays load-bearing (a missing fastembed means search cannot serve,
  # and going slim then would mean silent memory loss) — only the method is
  # cheaper. A present-but-broken install still fails at search time, which
  # exits 3 and falls back, so the safety property holds.
  if ! ls -d "$VENV"/lib/python*/site-packages/fastembed >/dev/null 2>&1; then
    echo "local-embed: fastembed not installed in $VENV" >&2
    return 3
  fi
  # "The index file exists" is not the same as "the index can answer". An index
  # built from an empty corpus is a valid file with zero chunks — and the
  # freshness path is required to write exactly that, so the empty case stops
  # rebuilding forever. A shell -f test reads that as healthy, which would send
  # SessionStart into slim mode against an index that returns nothing: silent
  # memory loss, the one outcome this gate exists to prevent. So the real check
  # (exists AND holds the corpus claimed AND has chunks) lives in one place,
  # local-embed.py health, and this delegates to it. Measured 0.044s — it loads
  # no model, and it costs less than the `import fastembed` probe it replaced.
  "$PY" "$SCRIPT" health --index-key "$(_key_for "${1:-global}")"
  return $?
}

case "$1" in
  health)
    # $2 = corpus name (optional). Absent means the global tier, which keeps
    # every existing caller working unchanged.
    _health "${2:-global}"
    exit $?
    ;;
  build)
    # $2=corpus-name (the index key) $3=corpus-dir. Exists so the freshness
    # path has one place to call that derives the key the same way search does.
    CORPUS_NAME="${2:-global}"; CORPUS_DIR="$3"
    if [ ! -x "$PY" ]; then
      echo "local-embed: venv python not found at $PY (run install.sh)" >&2
      exit 3
    fi
    if [ -z "$CORPUS_DIR" ]; then
      echo "local-embed: build needs <corpus-name> <corpus-dir>" >&2
      exit 1
    fi
    "$PY" "$SCRIPT" build --corpus "$CORPUS_DIR" --index-key "$(_key_for "$CORPUS_NAME")"
    exit $?
    ;;
  search)
    # $2=corpus-name (selects the tier index) $3=query $4=top-k
    # $5=corpus-dir (optional): when given, search refuses an index that was
    # built from a different directory. Tier names are <basename>-memory, so two
    # repos with the same basename in different parents would otherwise share an
    # index and answer each other's questions — and a moved repo would answer
    # from its old path. Both fail as exit 3 (fallback) instead of wrong memory.
    CORPUS_NAME="${2:-global}"; QUERY="$3"; TOPK="${4:-5}"; CORPUS_DIR="$5"
    if [ ! -x "$PY" ]; then
      echo "local-embed: venv python not found at $PY (run install.sh)" >&2
      exit 3
    fi
    if [ -n "$CORPUS_DIR" ]; then
      "$PY" "$SCRIPT" search "$QUERY" --top-k "$TOPK" \
          --index-key "$(_key_for "$CORPUS_NAME")" --corpus "$CORPUS_DIR"
    else
      "$PY" "$SCRIPT" search "$QUERY" --top-k "$TOPK" \
          --index-key "$(_key_for "$CORPUS_NAME")"
    fi
    exit $?
    ;;
  dedup)
    # $2=corpus-name (selects the tier to compare against) $3=candidate-file.
    # Embeds the candidate's text and
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
    "$PY" "$SCRIPT" search "$CAND_TEXT" --top-k 5 \
        --index-key "$(_key_for "${2:-global}")"
    exit $?
    ;;
  *)
    echo "usage: membackend-local-embed.sh search|dedup|build|health ..." >&2
    exit 1
    ;;
esac
