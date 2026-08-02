#!/bin/sh
# userpromptsubmit-memory-recall.sh — inject relevant memory, gated.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
# Guard the dot-source: a failed source aborts the whole script under dash even
# with set +e, which would emit a stderr error + non-zero exit on every prompt.
[ -f "$DIR/lib/memory-store.sh" ] && . "$DIR/lib/memory-store.sh"
INPUT=$(cat 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0
# skip trivial
words=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
case "$PROMPT" in y|yes|no|ok|continue|/*) exit 0 ;; esac
[ "$words" -ge 4 ] || exit 0

search() { # <index>
  if [ -n "$MEMORY_SEARCH_CMD" ]; then eval "$MEMORY_SEARCH_CMD"; return; fi
  leann search "$1" "$PROMPT" --top-k 8 --json --non-interactive --show-metadata 2>/dev/null
}
# Per-root global tier: derive the index name from the active config root so
# cl-p (~/.claude -> claude-memory-global) and cl-w (~/.claude-work ->
# claude-work-memory-global) never share global memory. Overridable for tests.
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
    python3 "$DIR/lib/memory-recall.py" --floor "${MEMORY_FLOOR:-0.5}" --top-k 3 --budget-tokens 400 \
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
