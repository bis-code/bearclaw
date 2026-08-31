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
INPUT=$(cat 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0
# skip trivial
words=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
case "$PROMPT" in y|yes|no|ok|continue|/*) exit 0 ;; esac
[ "$words" -ge 4 ] || exit 0

# Global tier prefers the opt-in memory-backend adapter (local-embed);
# "none" by default falls straight through. On any fallback signal — and
# always for the repo tier, which the adapter's v1 scope doesn't cover
# (a single corpus over memory-global/*.md, hooks/lib/local-embed.py) — falls
# back to bearclaw's own leann index, so an install that already has leann
# keeps its existing two-index recall unchanged. The adapter's JSONL
# {"score","path","snippet"} needs reshaping into the {"score","text",
# "metadata":{file_name}} array memory-recall.py expects; leann's own
# `--json --show-metadata` output is already in that shape, so the fallback
# passes straight through (as before this backend existed).
search() { # <index>
  if [ -n "$MEMORY_SEARCH_CMD" ]; then eval "$MEMORY_SEARCH_CMD"; return; fi
  if [ "$1" = "$GLOBAL_MEM_INDEX" ]; then
    _sr=$(membackend_search "$1" "$PROMPT" 8)
    if [ $? -eq 0 ] && [ -n "$_sr" ]; then
      printf '%s\n' "$_sr" | jq -s '[.[] | {score: .score, text: .snippet, metadata: {file_name: (.path | split("/") | last)}}]' 2>/dev/null
      return
    fi
  fi
  leann search "$1" "$PROMPT" --top-k 8 --json --non-interactive --show-metadata 2>/dev/null
}
# Global tier: derive the index name from the active config root
# (~/.claude -> claude-memory-global), so a session that runs against a
# different CLAUDE_CONFIG_DIR gets its own index rather than silently sharing
# one. Overridable for tests.
GLOBAL_MEM_INDEX="${GLOBAL_MEM_INDEX:-$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')-memory-global}"
GLOBAL_MEM_DIR="${GLOBAL_MEM_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-global}"
GLOBAL=$(search "$GLOBAL_MEM_INDEX")
REPO_JSON="[]"
REPO_MEM_DIR=""
# Repo tier: resolve the MAIN worktree (memory lives there, not in linked worktrees),
# so every worktree shares one <repo>-memory index — same resolution as
# sessionstart-load-memory.sh. Falls back to $CWD when not in a git repo.
if [ -n "$CWD" ]; then
  REPO_BASE="$CWD"
  GIT_COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$GIT_COMMON" ]; then
    MAIN_ROOT=$(dirname "$GIT_COMMON")
    [ -d "$MAIN_ROOT/.claude/memory" ] && REPO_BASE="$MAIN_ROOT"
  fi
  if [ -d "$REPO_BASE/.claude/memory" ]; then
    REPO_MEM_DIR="$REPO_BASE/.claude/memory"
    REPO_JSON=$(search "$(basename "$REPO_BASE")-memory"); [ -n "$REPO_JSON" ] || REPO_JSON="[]"
  fi
fi
MERGED=$(printf '%s\n%s' "${GLOBAL:-[]}" "$REPO_JSON" | jq -s 'add // []' 2>/dev/null)
[ -n "$MERGED" ] || exit 0
# Run the formatter; capture the <memory-context> block on stdout and the chosen
# entry-ids on fd 3 (the formatter emits one id per line there). The usage log
# feeds Phase-2 frequency/recency scoring back into the formatter on later turns.
IDS_FILE=$(mktemp 2>/dev/null) || IDS_FILE=""
BLOCK=$(printf '%s' "$MERGED" \
  | MEMORY_USAGE_LOG="$MEMSTORE_USAGE/recall-log.jsonl" \
    python3 "$DIR/lib/memory-recall.py" --floor "${MEMORY_FLOOR:-0.5}" \
      --top-k "${MEMORY_TOP_K:-4}" --budget-tokens "${MEMORY_BUDGET_TOKENS:-225}" \
      --mem-dir "$GLOBAL_MEM_DIR" --mem-dir "$REPO_MEM_DIR" \
    3>"${IDS_FILE:-/dev/null}" 2>/dev/null)
if [ -z "$BLOCK" ]; then
  [ -n "$IDS_FILE" ] && rm -f "$IDS_FILE"
  exit 0
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
