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
#                        MEMORY_LOAD_MAX_CHARS (default 8000) — caps the total
#                        SessionStart context; truncated at a line boundary
#                        with a trailing notice.
#
# Phase 1.5 — slim mode: skip eager memory dumps when a real memory backend
# serves recall on demand. Toggle (T9 — backend-aware, replaces the old
# leann-index-existence check):
#   membackend_name (hooks/lib/memory-backend.sh) != "none" -> slim load
#     (a configured backend serves bodies on demand; env MEMORY_BACKEND is
#     the test seam, same as every other adapter caller)
#   membackend_name == "none" -> eager/full load (today's behavior — this is
#     how bearclaw and any unconfigured machine degrade)
# No leann calls in this file.

set +e

GLOBAL_MEM_DIR="${GLOBAL_MEM_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-global}"
GLOBAL_MEM_INDEX="${GLOBAL_MEM_INDEX:-$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')-memory-global}"
ERRORS_TAIL="${ERRORS_TAIL:-5}"
MEMORY_LOAD_MAX_CHARS="${MEMORY_LOAD_MAX_CHARS:-8000}"

INPUT=$(cat 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"

# ---- resolve slim toggle via the backend adapter ----
DIR_MB=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$DIR_MB/lib/memory-backend.sh"
_slim=0
[ "$(membackend_name)" != "none" ] && _slim=1

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

if [ "$_slim" -eq 1 ]; then
  # Slim mode: skip eager dumps; let the recall hook serve bodies on-demand.
  OUT="${OUT}## Memory (recall-served)
Relevant memory + recent errors inject on-demand via the recall hook; search a symptom to pull it up.
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

# Memory review queue nudge removed 2026-08-30 (T9): the SessionEnd/PreCompact
# raw-capture backstop (sessionend-memory-capture.sh) and the memory-capture
# skill's deferred-drain path were retired along with leann's slim-gate
# dependency — Cognee (via lib/memory-backend.sh) replaces the need for a
# Claude-active distill queue.

# Cap total output: truncate to MEMORY_LOAD_MAX_CHARS at a line boundary and
# say so, rather than let one session's context balloon unbounded.
if [ -n "$OUT" ]; then
  _out_len=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
  if [ "$_out_len" -gt "$MEMORY_LOAD_MAX_CHARS" ]; then
    OUT=$(printf '%s' "$OUT" | awk -v max="$MEMORY_LOAD_MAX_CHARS" '
      { total += length($0) + 1
        if (total > max) exit
        print
      }')
    OUT="${OUT}
## Memory truncated at ${MEMORY_LOAD_MAX_CHARS} chars (set MEMORY_LOAD_MAX_CHARS to raise)"
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
