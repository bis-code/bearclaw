#!/usr/bin/env bats
# Tests for the identity gate. Every case here is one that actually reached
# this repo, or one whose exclusion was added to let real content through —
# so a future regex edit that "simplifies" the gate fails loudly instead of
# quietly publishing what the gate exists to stop.
#
# The gate scans `git ls-files` relative to its own location, so each test runs
# it inside a throwaway git repo containing a copy of the script.

setup() {
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gate-fix.XXXXXX")"
  mkdir -p "$FIXTURE/scripts"
  cp "$BATS_TEST_DIRNAME/../check-no-identity.sh" "$FIXTURE/scripts/"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email t@t
  git -C "$FIXTURE" config user.name t
  git -C "$FIXTURE" add -A
}

teardown() { rm -rf "$FIXTURE"; }

# plant CONTENT — write it into a tracked file so `git ls-files` sees it.
plant() {
  printf '%s\n' "$1" > "$FIXTURE/probe.txt"
  git -C "$FIXTURE" add -A
}

gate() { ( cd "$FIXTURE" && ./scripts/check-no-identity.sh ); }

@test "clean tree passes" {
  run gate
  [ "$status" -eq 0 ]
}

# --- check 2: contact details ------------------------------------------------

@test "git@ on a public forge is allowed (SSH login, not a person)" {
  plant 'GIT_CONFIG_VALUE_0="git@github.com:"'
  run gate
  [ "$status" -eq 0 ]
}

@test "a real address is still caught" {
  plant 'contact: someone@gmail.com'
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"email addresses"* ]]
}

@test "git@ on a non-public host is still caught (leaks a private hostname)" {
  plant 'remote = git@forge.internal-corp.net:team/repo.git'
  run gate
  [ "$status" -eq 1 ]
}

# --- check 1: absolute home paths --------------------------------------------

@test "an absolute /Users path is caught" {
  plant 'path = /Users/someone/projects/thing'
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"absolute home paths"* ]]
}

@test "a /home placeholder is allowed" {
  plant 'path = /home/user/mcps/foo-mcp'
  run gate
  [ "$status" -eq 0 ]
}

# --- check 4: layout assumptions ---------------------------------------------

@test "a non-dotfile home directory is caught (tilde form)" {
  plant 'write it to ~/Documents/Notes/inbox/'
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"personal home directories"* ]]
}

@test "a non-dotfile home directory is caught (\$HOME form)" {
  # A neutral stand-in, deliberately: the real path this case was written for
  # is itself a private name, and planting it here would publish the very
  # string the sibling private check exists to stop. (It did, and that check
  # blocked this file's first push.)
  plant 'for c in "$HOME/notes/vault/inbox"; do :; done'
  run gate
  [ "$status" -eq 1 ]
}

@test "a dotfile under home is allowed (config belongs there)" {
  plant 'CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"'
  run gate
  [ "$status" -eq 0 ]
}

@test "an obvious placeholder is allowed" {
  plant 'e.g. ~/foo or ~/foo/bar'
  run gate
  [ "$status" -eq 0 ]
}

# --- check 5: work/personal config-root split --------------------------------

@test "a second work config root is caught" {
  plant 'CLAUDE_WORK_HOME="${CLAUDE_WORK_HOME:-$HOME/.claude-work}"'
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"work/personal split"* ]]
}

@test "ordinary words containing 'work' are not caught" {
  plant 'workflow workspace worktree network framework workaround'
  run gate
  [ "$status" -eq 0 ]
}
