#!/bin/sh
# sessionend-memory-capture.sh — SessionEnd + PreCompact backstop. Writes a RAW
# capture pointer (NOT distilled memory) so endings without a /handoff still get
# reviewed: the next SessionStart nudges, and the memory-capture skill drains the
# queue (distill → dedup → AskUserQuestion → stage). NO LLM here — pointer only.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
[ -f "$DIR/lib/memory-store.sh" ] && . "$DIR/lib/memory-store.sh"

INPUT=$(cat 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TP=$(printf '%s' "$INPUT"  | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "SessionEnd"' 2>/dev/null)
[ -n "$SID" ] || SID="unknown"
[ -n "$CWD" ] || CWD="$PWD"

# Resolve the main-worktree basename as the project name (memory lives there).
PROJECT=$(basename "$CWD")
GIT_COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$GIT_COMMON" ]; then
  PROJECT=$(basename "$(dirname "$GIT_COMMON")")
fi
{ [ -z "$PROJECT" ] || [ "$PROJECT" = "/" ]; } && PROJECT="unknown-project"

SIGNAL_FILE="$MEMSTORE_SIGNALS/$SID.jsonl"
NOW=$(date +%s)

JSON=$(jq -nc \
  --arg session "$SID" \
  --arg transcript_path "$TP" \
  --arg signal_file "$SIGNAL_FILE" \
  --arg cwd "$CWD" \
  --arg project "$PROJECT" \
  --arg event "$EVENT" \
  --argjson ts "$NOW" \
  '{session:$session, transcript_path:$transcript_path, signal_file:$signal_file, cwd:$cwd, project:$project, event:$event, ts:$ts}' \
  2>/dev/null)
[ -n "$JSON" ] && memstore_enqueue_raw "$JSON" >/dev/null

# Bound the audit trail while we are already here. done/ had reached 490
# drained pointers over six weeks with nothing pruning it, plus orphaned
# signal files. Pending captures in raw/ are untouched — see memstore_prune_done.
command -v memstore_prune_done >/dev/null 2>&1 && memstore_prune_done

exit 0
