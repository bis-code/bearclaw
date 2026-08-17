#!/usr/bin/env bats
# Tests for the SessionStart memory loader. Points the hook at fixtures via env.
# ALL of these seams must be pinned or the suite reads/writes real machine state:
#   MEMORY_SLIM_LOAD  — unpinned, the hook falls through to ~/.claude/settings.json
#                        and takes the slim path, which never reads MEMORY.md/ERRORS.md.
#   MEMORY_STORE_DIR  — unpinned, the review-queue count reads the real capture queue.
#   MEMORY_BUILD_CMD  — the hook backgrounds memory-index-freshness.sh at the end,
#                        which (unpinned) shells out to the real `leann build`.
#   GLOBAL_MEM_INDEX  — defence in depth: even if a build ran, it must never be able
#                        to target the real "claude-memory-global" index name.
#   XDG_STATE_HOME    — keeps the freshness ".built" stamp files inside a dir the
#                        hook's detached background writer can outlive per-test
#                        teardown for (BATS_FILE_TMPDIR, cleaned once per file by
#                        bats itself), not in $FIX (removed by teardown() while
#                        the backgrounded memory-index-freshness.sh may still be
#                        writing — see git history for the race this caused) and
#                        not in the user's real ~/.local/state/claude-memory.

#   LEANN_INDEX_HOME  — the D2 slim fallback checks the recall index exists
#                        before honoring slim mode; point it at a fixture dir
#                        containing test-memory-global so slim tests exercise
#                        slim behavior (not the eager fallback).

HOOK() { printf '%s' "$1" | GLOBAL_MEM_DIR="$GMD" ERRORS_TAIL="${ETAIL:-5}" \
  MEMORY_SLIM_LOAD="${SLIM:-0}" MEMORY_STORE_DIR="$STORE" \
  MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX="test-memory-global" XDG_STATE_HOME="$BATS_FILE_TMPDIR/state" \
  LEANN_INDEX_HOME="$FIX/leann-idx" \
  sh "$BATS_TEST_DIRNAME/../../hooks/sessionstart-load-memory.sh"; }

setup() {
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/ssm.XXXXXX")"
  GMD="$FIX/global"; mkdir -p "$GMD"
  STORE="$FIX/store"; mkdir -p "$STORE/_pending/raw"
  mkdir -p "$FIX/leann-idx/test-memory-global"
}
teardown() { rm -rf "$FIX"; }

@test "always exits 0 even with everything absent" {
  rm -rf "$GMD"
  run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
}

@test "surfaces the global memory index" {
  printf -- '- [Thing](thing.md) — a hook\n' > "$GMD/MEMORY.md"
  run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Global memory")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Thing")'
}

@test "surfaces only the last ERRORS_TAIL entries (newest first)" {
  printf '# ERRORS\n\n## [d3] third\n## [d2] second\n## [d1] first\n' > "$GMD/ERRORS.md"
  ETAIL=2 run HOOK '{"cwd":"/tmp"}'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("third")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("second")'
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("first")' )
}

@test "surfaces repo-local index for the session cwd" {
  mkdir -p "$FIX/repo/.claude/memory"
  printf -- '- [RepoFact](rf.md) — local\n' > "$FIX/repo/.claude/memory/MEMORY.md"
  run HOOK "{\"cwd\":\"$FIX/repo\"}"
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("RepoFact")'
}

@test "emits nothing when no memory exists anywhere" {
  run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "slim mode emits the recall-served banner and skips eager dumps" {
  printf -- '- [Thing](thing.md) — a hook\n' > "$GMD/MEMORY.md"
  SLIM=1 run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("recall-served")'
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Thing")' )
}

@test "review queue is surfaced when raw captures are pending" {
  : > "$STORE/_pending/raw/abc123.json"
  run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Memory review queue")'
}
