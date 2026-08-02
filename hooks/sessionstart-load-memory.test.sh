#!/bin/sh
# Tests for sessionstart-load-memory.sh — focuses on the git-worktree resolution:
# canonical repo-local memory lives in the MAIN worktree, and must load from a
# LINKED worktree's cwd too. GLOBAL_MEM_DIR seam points at an empty temp dir so
# the real global memory doesn't bleed into assertions.
#
# Also covers Phase 1.5: memorySlimLoad toggle via MEMORY_SLIM_LOAD env.
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
# semantic-memory index or write real freshness stamps.
SAFE="MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX=test-memory-global XDG_STATE_HOME=$STATE_DIR"

# additionalContext for a given cwd, with global memory isolated to an empty dir
# Existing full-load assertions pin the toggle OFF (env seam) so they're
# deterministic regardless of the persistent memorySlimLoad setting (now true).
run(){ printf '{"cwd":"%s"}\n' "$1" | env $SAFE GLOBAL_MEM_DIR="$EMPTY" MEMORY_SLIM_LOAD=0 sh "$HOOK" 2>/dev/null \
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
printf '{"cwd":"%s"}\n' "$NONGIT" | env $SAFE GLOBAL_MEM_DIR="$EMPTY" MEMORY_SLIM_LOAD=0 sh "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "t3 non-git exits 0" || bad "t3 rc" "$rc"
run "$NONGIT" | grep -q "Repo-local memory" \
  && bad "t3" "unexpected repo-local section" || ok "t3 non-git: no repo-local section"

# T4–T7 removed 2026-06-30: the ROADMAP.md SessionStart nudge was retired when
# personal-project roadmaps moved to GitHub Issues (rules/solo-project-roadmap.md).
# The hook no longer emits a "Roadmap present" section.

# ---- review-queue nudge (Task 4) ----------------------------------------
# Point at a fresh store dir so no real state bleeds in.
STORE_DIR="$TMP/store"
export MEMORY_STORE_DIR="$STORE_DIR"

# run_store: like run() but also carries MEMORY_STORE_DIR
run_store(){ printf '{"cwd":"%s"}\n' "$MAIN" \
  | env $SAFE GLOBAL_MEM_DIR="$EMPTY" MEMORY_STORE_DIR="$STORE_DIR" sh "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""'; }

# T8: empty queue -> no nudge
run_store | grep -q "Memory review queue" \
  && bad "t8" "nudge shown with empty queue" || ok "t8 empty queue: no nudge"

# T9 & T10: with pending raw captures -> nudge appears with count
DIR_HOOK=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$DIR_HOOK/lib/memory-store.sh"; memstore_init
memstore_enqueue_raw '{"session":"a"}' >/dev/null
memstore_enqueue_raw '{"session":"b"}' >/dev/null
out_q=$(run_store)
printf '%s' "$out_q" | grep -q "Memory review queue" \
  && ok "t9 nudge appears with pending queue" || bad "t9" "nudge missing with pending queue"
printf '%s' "$out_q" | grep -q "2" \
  && ok "t10 pending count surfaced" || bad "t10" "pending count not in nudge"

# ---- Phase 1.5: memorySlimLoad toggle (MEMORY_SLIM_LOAD env seam) ----------
# Set up a global dir with both MEMORY.md and ERRORS.md containing canaries.
SLIM_GLOBAL="$TMP/slim-global"; mkdir -p "$SLIM_GLOBAL"
printf '# Global memory index\n- [foo](foo.md) — GLOBAL-MEM-CANARY\n' > "$SLIM_GLOBAL/MEMORY.md"
printf '## [2026-01-01] err one — fix one\n- **Trigger:** err-trigger-one\n- **Cause:** c\n- **Fix:** f\n- **Scope:** s\n' > "$SLIM_GLOBAL/ERRORS.md"

# repo for slim tests (reuse MAIN which has repo-local memory)

# run_slim: run hook with slim=ON and the populated global dir
run_slim(){ printf '{"cwd":"%s"}\n' "$MAIN" \
  | env $SAFE GLOBAL_MEM_DIR="$SLIM_GLOBAL" MEMORY_SLIM_LOAD=1 MEMORY_STORE_DIR="$STORE_DIR" \
    sh "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""'; }

# run_full: same global dir but slim=OFF — confirms eager content present
run_full(){ printf '{"cwd":"%s"}\n' "$MAIN" \
  | env $SAFE GLOBAL_MEM_DIR="$SLIM_GLOBAL" MEMORY_SLIM_LOAD=0 MEMORY_STORE_DIR="$STORE_DIR" \
    sh "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""'; }

slim_out=$(run_slim)
full_out=$(run_full)

# T11 (slim OFF): global MEMORY.md content appears
printf '%s' "$full_out" | grep -q "GLOBAL-MEM-CANARY" \
  && ok "t11 slim-off: global MEMORY.md appears" \
  || bad "t11" "global MEMORY.md missing when slim=0"

# T12 (slim OFF): global ERRORS content appears
printf '%s' "$full_out" | grep -q "err-trigger-one" \
  && ok "t12 slim-off: global ERRORS content appears" \
  || bad "t12" "global ERRORS missing when slim=0"

# T13 (slim OFF): repo-local MEMORY.md content appears
printf '%s' "$full_out" | grep -q "WORKTREE-CANARY-TOKEN" \
  && ok "t13 slim-off: repo-local MEMORY.md appears" \
  || bad "t13" "repo-local MEMORY.md missing when slim=0"

# T14 (slim ON): global MEMORY.md eager dump is ABSENT
printf '%s' "$slim_out" | grep -q "GLOBAL-MEM-CANARY" \
  && bad "t14" "global MEMORY.md appeared in slim mode" \
  || ok "t14 slim-on: global MEMORY.md eager dump absent"

# T15 (slim ON): global ERRORS eager dump is ABSENT
printf '%s' "$slim_out" | grep -q "err-trigger-one" \
  && bad "t15" "global ERRORS appeared in slim mode" \
  || ok "t15 slim-on: global ERRORS eager dump absent"

# T16 (slim ON): repo-local MEMORY.md eager dump is ABSENT
printf '%s' "$slim_out" | grep -q "WORKTREE-CANARY-TOKEN" \
  && bad "t16" "repo-local MEMORY.md appeared in slim mode" \
  || ok "t16 slim-on: repo-local MEMORY.md eager dump absent"

# T17 (slim ON): recall-served pointer line IS present
printf '%s' "$slim_out" | grep -q "recall-served" \
  && ok "t17 slim-on: recall-served pointer present" \
  || bad "t17" "recall-served pointer missing in slim mode"

# T19 (slim ON): capture nudge still appears when queue non-empty
# (STORE_DIR already has 2 items from T9/T10 above)
printf '%s' "$slim_out" | grep -q "Memory review queue" \
  && ok "t19 slim-on: capture nudge still present" \
  || bad "t19" "capture nudge missing in slim mode"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
