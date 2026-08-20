#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DEST="$(mktemp -d)"
}

teardown() { rm -rf "$DEST"; }

# Tests that actually execute install.sh MUST isolate the memory-index side
# effects from this machine's real state:
#   MEMORY_BUILD_CMD=true       -> no-ops the leann build
#   GLOBAL_MEM_INDEX=...        -> redirects away from the real
#                                  claude-memory-global index name
#   XDG_STATE_HOME=...          -> keeps memstore_init out of the real
#                                  ~/.local/state/claude-memory capture store
# See scripts/tests/settings-invariants.bats for the guard that enforces this.

@test "install.sh never touches global git config" {
  run grep -c 'git config --global' "$REPO/install.sh"
  [ "$output" = "0" ]
}

@test "install.sh never writes to ~/.gitconfig-*" {
  # Matches the prefix, not two specific suffixes: any identity file the
  # installer might reach for should fail this, not just the two that existed
  # when it was written.
  run grep -c 'gitconfig-' "$REPO/install.sh"
  [ "$output" = "0" ]
}

@test "install.sh never appends to .zshrc unconditionally" {
  run grep -c 'ZSHRC' "$REPO/install.sh"
  [ "$output" = "0" ]
}

@test "dry-run creates nothing" {
  run env MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX=test-memory-global \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    "$REPO/install.sh" --dry-run "$DEST"
  [ "$status" -eq 0 ]
  run find "$DEST" -mindepth 1
  [ -z "$output" ]
}

@test "install then uninstall leaves DEST empty of our symlinks" {
  MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX=test-memory-global \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    "$REPO/install.sh" "$DEST"
  [ -L "$DEST/settings.json" ]
  MEMORY_BUILD_CMD=true GLOBAL_MEM_INDEX=test-memory-global \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    "$REPO/install.sh" --uninstall "$DEST"
  [ ! -L "$DEST/settings.json" ]
  [ ! -L "$DEST/agents" ]
}
