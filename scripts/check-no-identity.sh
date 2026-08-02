#!/usr/bin/env bash
# Fails if any personally-identifying or work-org term reaches the public tree.
# This is the mechanical enforcement of the repo's genericization guarantee.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# \b[Tt]rip[_-]?[Ii]t\b catches the camel-case/joined spellings of the app
# name (TripIt, trip-it, trip_it) that the plain-string alternatives below
# miss. No space in the separator class — "trip it" (space-separated) is
# ordinary English ("does not trip it") and would false-positive; the
# space-separated app name is covered instead by the two case-sensitive
# literals "TRIP IT" and "Trip It" — capital-I "It" following "Trip" is not
# ordinary prose (English sentences don't capitalize "it" mid-clause), so
# this can't false-positive the way a lowercase "trip it" would. Do not add
# a lowercase "trip it" (space-separated) variant back — that's the exact
# false positive this comment warns against.
BANNED='scopito|heliscope|TRIP IT|Trip It|trip-it|ev-trip-it|web3-backend|baicoianu|/Users/|~/som|~/work|\bbis-code/claude-setup\b|\b[Tt]rip[_-]?[Ii]t\b|homelab|wevibbingiob'

# -H forces the filename prefix even when xargs' final batch is a single
# file (otherwise grep omits it, breaking both the file:line output below
# and the self-exclusion filter that depends on it).
hits=$(git ls-files -z \
  | xargs -0 grep -nEIH "$BANNED" 2>/dev/null \
  | grep -v '^scripts/check-no-identity.sh:' || true)

if [ -n "$hits" ]; then
  echo "identity leak — these tracked files contain banned terms:" >&2
  printf '%s\n' "$hits" >&2
  exit 1
fi
echo "ok: no identity leaks"

# Second, separate check: no work/personal config-root split. This repo is
# user-scope config for a computer — it has no folder-scope concept and must
# not encode one (e.g. a second "work" config root distinct from the primary
# one). Matches the concept via the naming pattern the split actually used
# (CLAUDE_WORK_HOME, ~/.claude-work, claude-work-memory-global, the cl-w
# alias) — NOT the substring "work" alone, which also appears in legitimate
# words this repo uses: workflow, workspace, worktree, network, framework,
# workaround, working. -i because the leaked forms varied in case
# (CLAUDE_WORK_HOME vs claude-work).
CONCEPT_BANNED='claude[_-]work|\bcl-w\b'

concept_hits=$(git ls-files -z \
  | xargs -0 grep -nEIHi "$CONCEPT_BANNED" 2>/dev/null \
  | grep -v '^scripts/check-no-identity.sh:' || true)

if [ -n "$concept_hits" ]; then
  echo "work/personal split leak — these tracked files encode a second work config root:" >&2
  printf '%s\n' "$concept_hits" >&2
  exit 1
fi
echo "ok: no work/personal config-root split"
exit 0
