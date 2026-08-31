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
# serves recall on demand. Toggle (backend-aware AND health-aware — a named
# backend that isn't actually serving must not go slim, or memory silently
# vanishes: no eager dump AND no recall):
#   membackend_name != "none" AND membackend_health == 0 -> slim load
#     (a configured, HEALTHY backend serves bodies on demand; env
#     MEMORY_BACKEND is the test seam, same as every other adapter caller)
#   membackend_name == "none" OR membackend_health != 0 -> eager/full load
#     (this is how bearclaw and any unconfigured machine degrade, and how a
#     configured-but-dead backend degrades — safe fallback, not silence)
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
# MEMBACKEND_LIB_DIR: this script lives in hooks/, not hooks/lib/, so
# memory-backend.sh's own $0-based colocation lookup (documented in its header)
# resolves to hooks/ and finds no membackend-<name>.sh — every dispatch,
# health included, then returns 3 "no backend". That silently pinned this gate
# to eager-load forever. Same seam userpromptsubmit-memory-recall.sh uses.
MEMBACKEND_LIB_DIR="${MEMBACKEND_LIB_DIR:-$DIR_MB/lib}"
. "$DIR_MB/lib/memory-backend.sh"
_slim=0
_mb_name=$(membackend_name)
# Health is asked PER TIER, not globally: with one index per corpus, "is the
# backend up" has no single answer. A repo whose index was never built is
# unhealthy for that repo and irrelevant to this gate, which decides only
# whether the GLOBAL corpus can be recalled on demand instead of eager-loaded.
# Passing the corpus name keeps that question answerable once other tiers exist.
if [ "$_mb_name" != "none" ] && membackend_health "$GLOBAL_MEM_INDEX" >/dev/null 2>&1; then
  _slim=1
fi

OUT=""

if [ "$_mb_name" != "none" ] && [ "$_slim" -eq 0 ]; then
  OUT="${OUT}note: memory backend '${_mb_name}' not ready — loaded full memory as fallback.
"
fi

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

# Keep every root's index fresh (processless; each rebuilds only if stale, and
# the machine-wide build cap in memory-index-freshness.sh stops several tiers
# from embedding at once). Roots come from memory-roots.sh so this cannot fall
# out of step with what the recall hook searches — a tier refreshed under one
# name and searched under another is a silent miss, not an error.
DIR_SS=$(CDPATH= cd "$(dirname "$0")" && pwd)
if [ -f "$DIR_SS/lib/memory-roots.sh" ]; then
  . "$DIR_SS/lib/memory-roots.sh"
  while IFS="	" read -r _fi _fd; do
    [ -n "$_fi" ] || continue
    sh "$DIR_SS/memory-index-freshness.sh" "$_fi" "$_fd" >/dev/null 2>&1 &
  done <<EOF
$(memroots_emit "$CWD")
EOF
fi

exit 0
