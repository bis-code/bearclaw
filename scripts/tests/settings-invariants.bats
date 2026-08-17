#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SETTINGS="$REPO/settings.json"
}

@test "settings.json is valid JSON" {
  run jq empty "$SETTINGS"
  [ "$status" -eq 0 ]
}

@test "effortLevel is present and set to auto" {
  run jq -r '.effortLevel // "MISSING"' "$SETTINGS"
  [ "$output" = "auto" ]
}

@test "SECURITY_REVIEW_MODEL points at a current-generation model" {
  run jq -r '.env.SECURITY_REVIEW_MODEL // "MISSING"' "$SETTINGS"
  [ "$output" = "claude-sonnet-5" ]
}

@test "no hardcoded absolute user paths in settings.json" {
  run grep -c '/Users/' "$SETTINGS"
  [ "$output" = "0" ]
}

@test "no hook script referenced in settings.json is missing from disk" {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  missing=""
  while read -r h; do
    [ -e "$REPO/hooks/$h" ] || missing="$missing $h"
  done < <(jq -r '.hooks | to_entries[] | .value[].hooks[] | select(.type=="command") | .command' "$SETTINGS" \
             | sed 's|.*hooks/||' | sort -u)
  [ -z "$missing" ]
}

@test "autopush is gone from settings.json" {
  run grep -c 'autopush' "$SETTINGS"
  [ "$output" = "0" ]
}

@test "no test file can trigger a real leann index build" {
  cd "$REPO"
  leaking=""
  for t in hooks/*.test.sh hooks/lib/*.test.sh scripts/tests/*.bats bin/*.test.sh; do
    [ -f "$t" ] || continue
    grep -qE 'sessionstart-load-memory|stop-memory-index-rebuild|memory-index-freshness|memory-index-build' "$t" || continue
    grep -v '^[[:space:]]*#' "$t" | grep -q 'MEMORY_BUILD_CMD=' || leaking="$leaking $t"
  done
  [ -z "$leaking" ] || { echo "test files can rebuild the real index:$leaking"; false; }
}
