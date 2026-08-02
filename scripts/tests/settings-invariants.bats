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
  # matches macOS or Linux home-directory-style absolute paths without
  # embedding either prefix contiguously, so this assertion doesn't itself
  # trip scripts/check-no-identity.sh
  run grep -cE '/(Users|home)/[^/]+' "$SETTINGS"
  [ "$output" = "0" ]
}

@test "no hook script referenced in settings.json is missing from disk" {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  missing=""
  while read -r h; do
    [ -e "$REPO/hooks/$h" ] || missing="$missing $h"
  done < <(jq -r '.hooks | to_entries[] | .value[].hooks[].command' "$SETTINGS" \
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

# install.sh transitively calls memory-index-freshness.sh but doesn't name it,
# so a bats file that merely invokes install.sh (e.g. scripts/tests/install.bats)
# passes the check above by never matching its hook-name pattern. Close that
# hole here: any test file invoking install.sh must also isolate the build.
# NOTE: this file is itself scanned by the loop below (scripts/tests/*.bats) and
# does not call install.sh, but it DOES contain the literal string "install.sh"
# in this comment and in the grep pattern beneath it — so it is excluded
# explicitly rather than relying on the pattern not matching itself (that
# implicit-non-match is exactly the footgun that made the check above silently
# self-pass in an earlier version of this file).
@test "no test file invokes install.sh without isolating MEMORY_BUILD_CMD" {
  cd "$REPO"
  leaking=""
  for t in hooks/*.test.sh hooks/lib/*.test.sh scripts/tests/*.bats bin/*.test.sh; do
    [ -f "$t" ] || continue
    case "$t" in scripts/tests/settings-invariants.bats) continue ;; esac
    grep -qF 'install.sh' "$t" || continue
    grep -v '^[[:space:]]*#' "$t" | grep -q 'MEMORY_BUILD_CMD=' || leaking="$leaking $t"
  done
  [ -z "$leaking" ] || { echo "test files invoke install.sh without MEMORY_BUILD_CMD:$leaking"; false; }
}

@test "public default permission mode is not bypassPermissions" {
  run jq -r '.permissions.defaultMode' "$SETTINGS"
  [ "$output" != "bypassPermissions" ]
}

@test "dangerous-mode prompt skips are absent" {
  run jq -r 'has("skipDangerousModePermissionPrompt") or has("skipAutoPermissionPrompt")' "$SETTINGS"
  [ "$output" = "false" ]
}

@test "no personal marketplaces are shipped" {
  run jq -r 'has("extraKnownMarketplaces")' "$SETTINGS"
  [ "$output" = "false" ]
}

@test "guard-destructive hook is registered" {
  run grep -c 'guard-destructive.py' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" != "0" ]
}

@test "no personal model pin is shipped" {
  run jq -r 'has("model")' "$SETTINGS"
  [ "$output" = "false" ]
}

@test "personal UI/notification taste keys are not shipped" {
  run jq -r '[.editorMode, .tui, .agentPushNotifEnabled, .inputNeededNotifEnabled, .preferredNotifChannel] | map(select(. != null)) | length' "$SETTINGS"
  [ "$output" = "0" ]
}
