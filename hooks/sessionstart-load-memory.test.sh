#!/bin/sh
# Tests for sessionstart-load-memory.sh — focuses on the git-worktree resolution:
# canonical repo-local memory lives in the MAIN worktree, and must load from a
# LINKED worktree's cwd too. GLOBAL_MEM_DIR seam points at an empty temp dir so
# the real global memory doesn't bleed into assertions.
#
# Also covers T9: the backend-aware slim-load gate (replaces the old
# leann-index-existence check). MEMORY_BACKEND is the seam (same contract as
# every other hooks/lib/memory-backend.sh caller): "none" -> eager load,
# anything else -> slim load.
HOOK="$(dirname "$0")/sessionstart-load-memory.sh"
TMP=$(mktemp -d)
EMPTY="$TMP/empty-global"; mkdir -p "$EMPTY"
# STATE_DIR lives OUTSIDE $TMP: the hook backgrounds memory-index-freshness.sh
# at the end of every HOOK() call, which is still mkdir/touch-ing under
# STATE_DIR after the hook (and this script) returns. Nesting it under $TMP
# raced the detached writer against the EXIT trap's cleanup. Cleaned in the
# trap below too, but tolerantly (`|| true`): the writer only does mkdir -p +
# touch (the real build is stubbed by MEMORY_BUILD_CMD=true) so it finishes in
# milliseconds and the common case cleans; on the rare loss, `|| true` means
# the suite still passes and one small dir survives instead of leaking always.
STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ssm-state.XXXXXX")
trap 'rm -rf "$TMP"; rm -rf "$STATE_DIR" 2>/dev/null || true' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

# Safety seam: the hook backgrounds memory-index-freshness.sh, which — unpinned —
# shells out to the real `leann build claude-memory-global` against whatever
# GLOBAL_MEM_DIR fixture is active. EVERY invocation of $HOOK below MUST route
# through this prefix (via `env $SAFE ...`) so no test can rebuild the real
# semantic-memory index or write real freshness stamps. MEMORY_BACKEND=none
# pins the slim/eager toggle deterministically (independent of whatever the
# real machine's settings.json memoryBackend is set to).
SAFE="MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX=test-memory-global XDG_STATE_HOME=$STATE_DIR MEMORY_BACKEND=none"

# additionalContext for a given cwd, with global memory isolated to an empty dir
run(){ printf '{"cwd":"%s"}\n' "$1" | env $SAFE GLOBAL_MEM_DIR="$EMPTY" sh "$HOOK" 2>/dev/null \
       | jq -r '.hookSpecificOutput.additionalContext // ""'; }

# Main repo with repo-local memory carrying a canary token
MAIN="$TMP/main"
mkdir -p "$MAIN/.claude/memory"
( cd "$MAIN" && git init -q && git config user.email t@t && git config user.name t \
    && git commit -q --allow-empty -m init )
printf '# MEMORY index\n- [canary](x.md) — WORKTREE-CANARY-TOKEN\n' > "$MAIN/.claude/memory/MEMORY.md"

# T1: cwd = main repo -> loads repo-local memory
run "$MAIN" | grep -q "WORKTREE-CANARY-TOKEN" \
  && ok "t1 main repo loads repo-local memory" || bad "t1" "canary missing"

# T2: cwd = linked worktree -> resolves git-common-dir to MAIN repo's memory
WT="$TMP/wt"
( cd "$MAIN" && git worktree add -q "$WT" -b wt-branch >/dev/null 2>&1 )
run "$WT" | grep -q "WORKTREE-CANARY-TOKEN" \
  && ok "t2 worktree resolves to MAIN repo memory" || bad "t2" "worktree did not resolve to main"

# T3: cwd = non-git dir, no memory -> no repo-local section, exit 0
NONGIT="$TMP/nongit"; mkdir -p "$NONGIT"
printf '{"cwd":"%s"}\n' "$NONGIT" | env $SAFE GLOBAL_MEM_DIR="$EMPTY" sh "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "t3 non-git exits 0" || bad "t3 rc" "$rc"
run "$NONGIT" | grep -q "Repo-local memory" \
  && bad "t3" "unexpected repo-local section" || ok "t3 non-git: no repo-local section"

# T4–T7 removed 2026-06-30: the ROADMAP.md SessionStart nudge was retired when
# personal-project roadmaps moved to GitHub Issues (rules/solo-project-roadmap.md).
# The hook no longer emits a "Roadmap present" section.

# T8–T10 (memory review queue nudge) removed 2026-08-30 (T9): the SessionEnd/
# PreCompact raw-capture backstop and the memory-capture skill's deferred-drain
# path were retired along with leann's slim-gate dependency. The hook no
# longer sources memory-store.sh or emits a "Memory review queue" section.

# ---- T9: backend-aware slim toggle (MEMORY_BACKEND env seam) --------------
# Set up a global dir with both MEMORY.md and ERRORS.md containing canaries.
SLIM_GLOBAL="$TMP/slim-global"; mkdir -p "$SLIM_GLOBAL"
printf '# Global memory index\n- [foo](foo.md) — GLOBAL-MEM-CANARY\n' > "$SLIM_GLOBAL/MEMORY.md"
printf '## [2026-01-01] err one — fix one\n- **Trigger:** err-trigger-one\n- **Cause:** c\n- **Fix:** f\n- **Scope:** s\n' > "$SLIM_GLOBAL/ERRORS.md"

# repo for slim tests (reuse MAIN which has repo-local memory)

# run_slim: run hook with a configured (non-none) backend -> slim path
run_slim(){ printf '{"cwd":"%s"}\n' "$MAIN" \
  | env MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX=test-memory-global XDG_STATE_HOME="$STATE_DIR" \
    MEMORY_BACKEND=local-embed GLOBAL_MEM_DIR="$SLIM_GLOBAL" \
    sh "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""'; }

# run_full: same global dir but backend=none -> confirms eager content present
run_full(){ printf '{"cwd":"%s"}\n' "$MAIN" \
  | env $SAFE GLOBAL_MEM_DIR="$SLIM_GLOBAL" \
    sh "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""'; }

slim_out=$(run_slim)
full_out=$(run_full)

# T11 (backend=none): global MEMORY.md content appears
printf '%s' "$full_out" | grep -q "GLOBAL-MEM-CANARY" \
  && ok "t11 backend=none: global MEMORY.md appears (eager)" \
  || bad "t11" "global MEMORY.md missing when backend=none"

# T12 (backend=none): global ERRORS content appears
printf '%s' "$full_out" | grep -q "err-trigger-one" \
  && ok "t12 backend=none: global ERRORS content appears (eager)" \
  || bad "t12" "global ERRORS missing when backend=none"

# T13 (backend=none): repo-local MEMORY.md content appears
printf '%s' "$full_out" | grep -q "WORKTREE-CANARY-TOKEN" \
  && ok "t13 backend=none: repo-local MEMORY.md appears (eager)" \
  || bad "t13" "repo-local MEMORY.md missing when backend=none"

# T14 (backend=local-embed): global MEMORY.md eager dump is ABSENT
printf '%s' "$slim_out" | grep -q "GLOBAL-MEM-CANARY" \
  && bad "t14" "global MEMORY.md appeared with backend=local-embed" \
  || ok "t14 backend=local-embed: global MEMORY.md eager dump absent (slim)"

# T15 (backend=local-embed): global ERRORS eager dump is ABSENT
printf '%s' "$slim_out" | grep -q "err-trigger-one" \
  && bad "t15" "global ERRORS appeared with backend=local-embed" \
  || ok "t15 backend=local-embed: global ERRORS eager dump absent (slim)"

# T16 (backend=local-embed): repo-local MEMORY.md eager dump is ABSENT
printf '%s' "$slim_out" | grep -q "WORKTREE-CANARY-TOKEN" \
  && bad "t16" "repo-local MEMORY.md appeared with backend=local-embed" \
  || ok "t16 backend=local-embed: repo-local MEMORY.md eager dump absent (slim)"

# T17 (backend=local-embed): recall-served pointer line IS present
printf '%s' "$slim_out" | grep -q "recall-served" \
  && ok "t17 backend=local-embed: recall-served pointer present (slim)" \
  || bad "t17" "recall-served pointer missing with backend=local-embed"

# T18: no leann call anywhere in the hook's own EXECUTABLE source (T9
# requirement — the backend-aware gate must not invoke leann directly; recall
# stays delegated to the adapter / recall hook). Comments are allowed to say
# the word (they document what was removed); only non-comment lines count.
if grep -v '^[[:space:]]*#' "$HOOK" | grep -qi 'leann'; then
  bad "t18" "sessionstart-load-memory.sh still invokes leann"
else
  ok "t18 no leann invocation in sessionstart-load-memory.sh"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
