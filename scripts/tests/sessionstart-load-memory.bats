#!/usr/bin/env bats
# Tests for the SessionStart memory loader. Points the hook at fixtures via env.
# ALL of these seams must be pinned or the suite reads/writes real machine state:
#   MEMORY_BACKEND    — unpinned, the hook falls through to the real
#                        ~/.claude/settings.json memoryBackend key. "none" pins
#                        the eager path; any other (healthy, per STUB_LIB below)
#                        value pins the slim path (backend- AND health-aware
#                        gate via hooks/lib/memory-backend.sh).
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

# STUB_LIB stands in for hooks/lib/membackend-<name>.sh: the slim gate is
# HEALTH-gated, not just name-gated (a named-but-dead backend must fall back
# to eager — see hooks/lib/memory-backend.sh membackend_health). The real
# membackend-local-embed.sh's health depends on this machine's venv/index
# actually existing, which these tests must not rely on; STUB_HEALTH_RC lets
# a test pick healthy (0, default) or unhealthy (3).
STUB_LIB="$BATS_FILE_TMPDIR/stub-membackend-lib"

HOOK() { printf '%s' "$1" | GLOBAL_MEM_DIR="$GMD" ERRORS_TAIL="${ETAIL:-5}" \
  MEMORY_BACKEND="${BACKEND:-none}" MEMBACKEND_LIB_DIR="$STUB_LIB" STUB_HEALTH_RC="${HEALTH_RC:-0}" \
  MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX="test-memory-global" XDG_STATE_HOME="$BATS_FILE_TMPDIR/state" \
  MEMORY_LOAD_MAX_CHARS="${MAXCHARS:-8000}" \
  sh "$BATS_TEST_DIRNAME/../../hooks/sessionstart-load-memory.sh"; }

setup_file() {
  mkdir -p "$BATS_FILE_TMPDIR/stub-membackend-lib"
  cat > "$BATS_FILE_TMPDIR/stub-membackend-lib/membackend-local-embed.sh" <<'STUBEOF'
#!/bin/sh
case "$1" in
  health) exit "${STUB_HEALTH_RC:-0}" ;;
  *) exit 3 ;;
esac
STUBEOF
  chmod +x "$BATS_FILE_TMPDIR/stub-membackend-lib/membackend-local-embed.sh"
}

setup() {
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/ssm.XXXXXX")"
  GMD="$FIX/global"; mkdir -p "$GMD"
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

@test "a configured (non-none) backend emits the recall-served banner and skips eager dumps" {
  printf -- '- [Thing](thing.md) — a hook\n' > "$GMD/MEMORY.md"
  BACKEND=local-embed run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("recall-served")'
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Thing")' )
}

@test "a configured but UNHEALTHY backend falls back to eager load with a note" {
  printf -- '- [Thing](thing.md) — a hook\n' > "$GMD/MEMORY.md"
  BACKEND=local-embed HEALTH_RC=3 run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Thing")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("not ready")'
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("recall-served")' )
}

@test "backend=none loads eagerly (default degrade for bearclaw / unconfigured machines)" {
  printf -- '- [Thing](thing.md) — a hook\n' > "$GMD/MEMORY.md"
  BACKEND=none run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Thing")'
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("recall-served")' )
}

@test "output under MEMORY_LOAD_MAX_CHARS is not truncated" {
  printf -- '- [Thing](thing.md) — a hook\n' > "$GMD/MEMORY.md"
  MAXCHARS=8000 run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Memory truncated")' )
}

@test "output over MEMORY_LOAD_MAX_CHARS is truncated at a line boundary with a notice" {
  awk 'BEGIN { for (i = 1; i <= 300; i++) print "- [Item" i "](item" i ".md) — a fact about item " i }' > "$GMD/MEMORY.md"
  MAXCHARS=500 run HOOK '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Memory truncated at 500 chars")'
  # never keeps a later, unreachable item — proves the cut, not just the notice
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Item300")' )
  # notice sits at the very end and the line before it is a complete, unbroken line
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext' > "$FIX/ctx.txt"
  tail -1 "$FIX/ctx.txt" | grep -q "^## Memory truncated at 500 chars"
  kept_last=$(grep -c '^- \[Item' "$FIX/ctx.txt")
  [ "$kept_last" -gt 0 ]
  grep '^- \[Item' "$FIX/ctx.txt" | tail -1 | grep -qE '^- \[Item[0-9]+\]\(item[0-9]+\.md\) — a fact about item [0-9]+$'
}
