#!/usr/bin/env bats
# Behavioural coverage for hooks/guard-destructive.py — the PreToolUse guard
# that blocks catastrophic destructive shell commands regardless of
# permission mode. Covers both directions: it must deny real destructive
# invocations AND must not flag destructive-looking strings that never
# execute (echo, comments, deep/narrow deletes).
#
# HOME is faked per-test (never the real machine home) so assertions never
# depend on, or leak, this machine's actual directory layout, and so paths
# are built at runtime rather than hardcoded.

GUARD="$BATS_TEST_DIRNAME/../../hooks/guard-destructive.py"

setup() {
  # Explicit /tmp, not the bare mktemp default: on macOS $TMPDIR resolves
  # under /var/folders/..., which the guard's own SYS denylist blocks —
  # that would make "allow" assertions on deep paths fail for the wrong
  # reason. /tmp is neutral on both macOS and Linux.
  FAKE_HOME="$(mktemp -d /tmp/guard-home.XXXXXX)/tester"
  mkdir -p "$FAKE_HOME"
}

teardown() {
  rm -rf "$(dirname "$FAKE_HOME")"
}

# Feeds a Bash command through the guard exactly as the harness does: a JSON
# payload with tool_name=Bash and tool_input.command on stdin.
run_guard() {
  local command="$1"
  local payload
  payload="$(jq -n --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}')"
  run env HOME="$FAKE_HOME" python3 "$GUARD" <<<"$payload"
}

assert_deny() {
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"deny"'* || "$output" == *'"permissionDecision": "deny"'* ]]
}

assert_allow() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- MUST DENY ---------------------------------------------------------

@test "denies rm -rf ~" {
  run_guard 'rm -rf ~'
  assert_deny
}

@test "denies rm -rf \$HOME" {
  run_guard 'rm -rf $HOME'
  assert_deny
}

@test "denies rm -rf of a shallow tilde path (~/foo)" {
  run_guard 'rm -rf ~/foo'
  assert_deny
}

@test "denies rm -rf of a shallow absolute home path built from the runtime home root" {
  # Same target as ~/targetdir but spelled out as an absolute path rooted at
  # the runtime-derived home directory, not a hardcoded platform prefix.
  run_guard "rm -rf $FAKE_HOME/targetdir"
  assert_deny
}

@test "denies git clean -fdx" {
  run_guard 'git clean -fdx'
  assert_deny
}

@test "denies rm -rf /*" {
  run_guard 'rm -rf /*'
  assert_deny
}

@test "denies recursive chmod over home" {
  run_guard 'chmod -R 777 ~'
  assert_deny
}

# --- MUST ALLOW ---------------------------------------------------------

@test "allows rm -rf node_modules" {
  run_guard 'rm -rf node_modules'
  assert_allow
}

@test "allows rm -rf dist" {
  run_guard 'rm -rf dist'
  assert_allow
}

@test "allows rm -rf of a deep path under home" {
  run_guard "rm -rf $FAKE_HOME/projects/a/b/c/deep"
  assert_allow
}

@test "allows ls -la" {
  run_guard 'ls -la'
  assert_allow
}

@test "allows echo of a destructive-looking string (parser distinguishes real invocations)" {
  run_guard 'echo "rm -rf ~/foo"'
  assert_allow
}

# Regression test: HOME containing a redundant "//" (e.g. from a TMPDIR that
# already ends in "/") must not defeat the shallow-home-path check. The
# guard normalizes HOME before comparing prefixes; without that, the
# unnormalized HOME string fails to prefix-match the normpath'd target and
# the deny silently never fires.
@test "denies a shallow path even when HOME has a redundant double slash" {
  local doubled_home="${FAKE_HOME%/tester}//tester"
  local payload
  payload="$(jq -n --arg c 'rm -rf ~/foo' '{tool_name: "Bash", tool_input: {command: $c}}')"
  run env HOME="$doubled_home" python3 "$GUARD" <<<"$payload"
  assert_deny
}
