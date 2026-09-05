#!/usr/bin/env bash
# Pre-push lint for claude-setup. Catches malformed JSON / broken shell
# before they reach origin and bork the next session start.
#
# Installed by install.sh as a symlink: .git/hooks/pre-push -> this file.
# Skips if scripts are missing or jq/bash aren't on PATH.

set -euo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO" ] || { echo "pre-push: not in a git repo" >&2; exit 0; }
cd "$REPO"

fail=0

# JSON validity — every tracked .json file, excluding plugins/ runtime state.
if command -v jq >/dev/null 2>&1; then
    while IFS= read -r f; do
        case "$f" in plugins/*) continue ;; esac
        if ! jq empty "$f" >/dev/null 2>&1; then
            echo "pre-push: invalid JSON: $f" >&2
            fail=1
        fi
    done < <(git ls-files '*.json')
fi

# Shell syntax — every tracked .sh file.
while IFS= read -r f; do
    if ! bash -n "$f" 2>/dev/null; then
        echo "pre-push: bash -n failed: $f" >&2
        fail=1
    fi
done < <(git ls-files '*.sh')

# Optional shellcheck if installed — warnings only, never blocks.
if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r f; do
        shellcheck -S warning "$f" 2>&1 | head -10 || true
    done < <(git ls-files '*.sh') 1>&2
fi

# Full test suite — blocks the push on any failure.
#
# Run it with git's per-hook env stripped. git exports GIT_DIR to every hook;
# from a normal checkout that is the relative ".git", which harmlessly resolves
# to each test's own temp repo, but from a worktree it is ABSOLUTE and points
# every temp repo the suite creates back at the real one. Six suites failed
# that way on a worktree push while passing standalone, which reads as "the
# tests are broken" rather than "the gate poisoned them" — and the fixtures
# then committed onto the live branch and rewrote its config.
if [ -x "$REPO/scripts/test-all.sh" ]; then
    if ! (unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR; \
          "$REPO/scripts/test-all.sh") >&2; then
        echo "pre-push: test suite failed" >&2
        fail=1
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "pre-push: blocking push — fix the issues above (or use --no-verify if you know what you're doing)" >&2
    exit 1
fi

exit 0
