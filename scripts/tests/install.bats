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

@test "install.sh never chmods the source checkout" {
  # It used to, and it had to: when install.sh symlinked, DEST and REPO were
  # the same inodes. A copy severs that, so a repo-side chmod now only rewrites
  # tracked modes in the user's checkout — `git status` dirty after an install
  # that changed nothing they wrote, including 644 sourced libraries flipped to
  # 755 against their own headers. The installed tree is the only tree whose
  # modes are ours to assert.
  run grep -c 'chmod +x "\$REPO' "$REPO/install.sh"
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

# Copy-on-install: fresh install into an empty DEST produces real files/dirs,
# never symlinks — Claude Code atomic-writes settings.json on /config etc.,
# which used to replace a symlink with a real file and drop repo-only keys.
# INSTALL_TEST_STOP_AFTER_COPY=1 stops right after the copy + .installed-from
# write, before install.sh's machine-wide side effects (plugin install,
# memory-index build) that a test must never trigger.
@test "install copies real files and dirs, not symlinks" {
  INSTALL_TEST_STOP_AFTER_COPY=1 "$REPO/install.sh" "$DEST"
  for entry in CLAUDE.md .mcp.json settings.json statusline.sh; do
    [ -f "$DEST/$entry" ] && [ ! -L "$DEST/$entry" ]
  done
  for entry in rules skills hooks agents bin memory-global; do
    [ -d "$DEST/$entry" ] && [ ! -L "$DEST/$entry" ]
  done
  # spot-check actual content landed, not just empty dirs
  [ -f "$DEST/hooks/sessionstart-heal-settings.sh" ]
  # no top-level symlink anywhere under DEST pointing back at the repo
  run find "$DEST" -maxdepth 1 -type l
  [ -z "$output" ]
}

@test "install records .installed-from with repo= and sha=" {
  INSTALL_TEST_STOP_AFTER_COPY=1 "$REPO/install.sh" "$DEST"
  [ -f "$DEST/.installed-from" ]
  REPO_LINE=$(sed -n 's/^repo=//p' "$DEST/.installed-from")
  SHA_LINE=$(sed -n 's/^sha=//p' "$DEST/.installed-from")
  # -e, not -d: a git worktree's .git is a plain file, not a directory.
  [ -n "$REPO_LINE" ] && [ -e "$REPO_LINE/.git" ]
  [ "$SHA_LINE" = "$(git -C "$REPO" rev-parse HEAD)" ]
}

# Reviewer-flagged guard bypass: dirname("/")+basename("/") used to join into
# the literal "///", which the "/" case pattern did not match.
@test "DEST=/ is refused before anything is touched" {
  run "$REPO/install.sh" /
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to install"* ]]
}

@test "DEST=\$HOME is refused too (same guard, the other named case)" {
  run "$REPO/install.sh" "$HOME"
  [ "$status" -ne 0 ]
}

@test "re-running into the same DEST is idempotent" {
  INSTALL_TEST_STOP_AFTER_COPY=1 "$REPO/install.sh" "$DEST"
  run env INSTALL_TEST_STOP_AFTER_COPY=1 "$REPO/install.sh" "$DEST"
  [ "$status" -eq 0 ]
  [ -f "$DEST/CLAUDE.md" ] && [ ! -L "$DEST/CLAUDE.md" ]
}
