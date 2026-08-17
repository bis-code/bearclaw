#!/bin/sh
# sessionstart-load-memory.sh — SessionStart hook (user scope, all projects).
#
# Surfaces memory regardless of cwd, fixing the gap where the harness only
# natively loads ~/.claude/projects/<cwd>/memory/:
#   1. global memory index   ($GLOBAL_MEM_DIR/MEMORY.md)
#   2. recent global ERRORS  ($GLOBAL_MEM_DIR/ERRORS.md, last $ERRORS_TAIL entries)
#   3. repo-local index      (<session-cwd>/.claude/memory/MEMORY.md)
# Best-effort; missing files are skipped. Always exits 0 — never block startup.
#
# Env overrides (tests): GLOBAL_MEM_DIR (default ~/.claude/memory-global),
#                        ERRORS_TAIL    (default 5)
#
# Phase 1.5 — slim mode: skip eager memory dumps when recall hook serves bodies
# on-demand. Toggle resolution (in precedence order):
#   1. MEMORY_SLIM_LOAD env: "1"/"true" = on, "0"/"false" = off (test seam)
#   2. settings.json key memorySlimLoad (boolean)
#   3. default OFF (current full-load behavior)

set +e

GLOBAL_MEM_DIR="${GLOBAL_MEM_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-global}"
GLOBAL_MEM_INDEX="${GLOBAL_MEM_INDEX:-$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')-memory-global}"
ERRORS_TAIL="${ERRORS_TAIL:-5}"

INPUT=$(cat 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"

# ---- resolve slim toggle ----
_slim=0
if [ -n "$MEMORY_SLIM_LOAD" ]; then
  case "$MEMORY_SLIM_LOAD" in
    1|true)  _slim=1 ;;
    0|false) _slim=0 ;;
  esac
else
  _SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$_SETTINGS" ]; then
    _val=$(jq -r '.memorySlimLoad // empty' "$_SETTINGS" 2>/dev/null)
    [ "$_val" = "true" ] && _slim=1
  fi
fi

# D2 fallback: slim mode trusts the recall hook, so verify its index actually
# EXISTS before honoring the toggle — a missing index under slim mode caused a
# session-long silent memory blackout (2026-08-16). Falls back to eager load
# with a visible notice. LEANN_INDEX_HOME is the test seam.
_SLIM_FALLBACK=0
if [ "$_slim" -eq 1 ] && [ ! -d "${LEANN_INDEX_HOME:-$HOME/.leann/indexes}/$GLOBAL_MEM_INDEX" ]; then
  _slim=0
  _SLIM_FALLBACK=1
fi

OUT=""

# Surface a broken index build (marker written by lib/memory-index-build.sh).
# Without this, a dead index means recall silently returns nothing all session.
_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"
for _e in "$_STATE"/*.build.err; do
  [ -f "$_e" ] || continue
  OUT="${OUT}## Memory index BROKEN
$(head -1 "$_e") Full log: ${_e%.err}.log — recall is degraded until fixed.
"
done

if [ "$_SLIM_FALLBACK" -eq 1 ]; then
  OUT="${OUT}## Memory notice
recall index missing (${LEANN_INDEX_HOME:-$HOME/.leann/indexes}/$GLOBAL_MEM_INDEX) — memory loaded eagerly this session; the index rebuilds at session start (doctor group 10 has details).
"
fi

if [ "$_slim" -eq 1 ]; then
  # Slim mode: skip eager dumps; let the recall hook serve bodies on-demand.
  OUT="${OUT}## Memory (recall-served)
Relevant memory + recent errors inject on-demand via the recall hook; search a symptom, or invoke /memory-capture to review the queue.
"
else
  if [ -f "$GLOBAL_MEM_DIR/MEMORY.md" ]; then
    OUT="${OUT}## Global memory (loaded every session)
$(cat "$GLOBAL_MEM_DIR/MEMORY.md")

"
  fi

  if [ -f "$GLOBAL_MEM_DIR/ERRORS.md" ]; then
    RECENT=$(awk -v n="$ERRORS_TAIL" '/^## /{c++} c>=1 && c<=n {print}' "$GLOBAL_MEM_DIR/ERRORS.md")
    if [ -n "$RECENT" ]; then
      OUT="${OUT}## Recent global ERRORS (last ${ERRORS_TAIL})
${RECENT}

"
    fi
  fi
fi

# Resolve the repo-local memory dir. In a git worktree the canonical memory
# lives in the MAIN worktree, not the linked worktree's cwd — so resolve via
# --git-common-dir (points at <main>/.git) and take its parent. This makes one
# memory store load in the main repo AND every worktree. Falls back to $CWD
# when not in a repo (or on git too old for --path-format).
MEM_BASE="$CWD"
GIT_COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$GIT_COMMON" ]; then
  MAIN_ROOT=$(dirname "$GIT_COMMON")
  [ -d "$MAIN_ROOT/.claude/memory" ] && MEM_BASE="$MAIN_ROOT"
fi

if [ "$_slim" -eq 0 ] && [ -f "$MEM_BASE/.claude/memory/MEMORY.md" ]; then
  OUT="${OUT}## Repo-local memory ($MEM_BASE)
$(cat "$MEM_BASE/.claude/memory/MEMORY.md")
"
fi

# Roadmap nudge removed 2026-06-30: personal-project roadmaps moved to GitHub Issues
# (rules/solo-project-roadmap.md, loaded every session, carries the "gh issue list at
# session start" discipline). No committed ROADMAP.md to auto-read — that file grew to
# 91 KB and taxed every session start.

# Memory review queue: if the SessionEnd/PreCompact backstop staged raw captures
# (endings without a /handoff), nudge Claude to drain them via memory-capture.
# Hooks can't distill — this just points; the skill does the LLM work.
DIR_MS=$(CDPATH= cd "$(dirname "$0")" && pwd)
if [ -f "$DIR_MS/lib/memory-store.sh" ]; then
  . "$DIR_MS/lib/memory-store.sh"
  PENDING_N=$(memstore_list_raw | wc -l | tr -d ' ')
  if [ "${PENDING_N:-0}" -gt 0 ]; then
    OUT="${OUT}## Memory review queue
$PENDING_N raw session-capture(s) await review. Invoke the memory-capture skill (deferred-drain) to distill → dedup → accept/reject into repo-local memory. Nothing is written without your explicit accept.
"
  fi
fi

if [ -n "$OUT" ]; then
  jq -n --arg ctx "$OUT" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
fi

# keep the recall index fresh (processless; rebuilds only if stale)
DIR_SS=$(CDPATH= cd "$(dirname "$0")" && pwd)
sh "$DIR_SS/memory-index-freshness.sh" "$GLOBAL_MEM_INDEX" "$GLOBAL_MEM_DIR" >/dev/null 2>&1 &
if [ -d "$MEM_BASE/.claude/memory" ]; then
  sh "$DIR_SS/memory-index-freshness.sh" "$(basename "$MEM_BASE")-memory" "$MEM_BASE/.claude/memory" >/dev/null 2>&1 &
fi

exit 0
