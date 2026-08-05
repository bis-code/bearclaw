#!/usr/bin/env bash
# Fails if anything machine-specific or personally-identifying reaches the tree.
#
# These checks are STRUCTURAL on purpose. An earlier version carried a literal
# denylist of the maintainer's employer, project and host names — which meant
# this public file published the exact strings it existed to keep out. A public
# denylist of private terms is self-defeating. Anything name-specific belongs in
# a private pre-publish check, not here.
#
# What this catches is what actually matters for a shared config: absolute paths
# from someone's machine, contact details, and network addresses. Those are the
# forms a leak takes regardless of whose fork it is, so this is also the check a
# contributor wants running on their own PR.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# -H forces the filename prefix even when xargs' final batch is a single file
# (otherwise grep omits it, breaking both the file:line output and the
# self-exclusion filter that depends on it).
scan() { git ls-files -z | xargs -0 grep -nEIH "$1" 2>/dev/null | grep -v '^scripts/check-no-identity.sh:' || true; }

fail=0
report() { # <label> <hits>
  [ -n "$2" ] || return 0
  echo "$1" >&2
  printf '%s\n' "$2" >&2
  fail=1
}

# grep -E has no negative lookahead, so every exclusion below is a `grep -v`
# filter on the results rather than a cleverer pattern. Keep it that way: an
# unsupported construct fails open and the check silently passes.
drop() { grep -viE "$1" || true; }

# 1. Absolute home paths. /Users/<name> (macOS) and /home/<name> (Linux) are
#    always somebody's machine. Obvious fixture placeholders are allowed so
#    tests can still exercise path handling.
report "absolute home paths — use \$HOME, ~, or a placeholder like /home/user:" \
  "$(scan '/Users/[a-zA-Z0-9._-]+|/home/[a-zA-Z0-9._-]+' \
     | drop '/home/(user|you|x|me|test|example|runner)(/|\b)')"

# 2. Contact details. The domain must end in a real-looking TLD that is not a
#    file extension — "icon_512x512@2x.png" is a filename, not an address.
report "email addresses — no personal contact details in a shared config:" \
  "$(scan '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
     | drop 'noreply@anthropic|users\.noreply\.github\.com|example\.(com|org)|user@host|@ns\.adobe|@[a-zA-Z0-9.-]*\.(png|jpg|jpeg|gif|svg|js|ts|sh|md|json|py|txt|html|css)\b')"

# 3. Network addresses. Loopback and unspecified are fine; anything else is
#    somebody's host. Version-number-shaped strings are excluded by requiring
#    four octets and dropping the common false positives.
report "IP addresses — no host addresses in a shared config:" \
  "$(scan '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
     | drop '127\.0\.0\.1|0\.0\.0\.0|255\.255\.255|localhost')"

[ "$fail" -eq 0 ] && echo "ok: no machine-specific or identifying strings"

# 4. No work/personal config-root split. This repo is user-scope config for a
#    computer — it has no folder-scope concept and must not encode one (e.g. a
#    second "work" config root distinct from the primary one). Matches the
#    concept via the naming pattern the split actually used (CLAUDE_WORK_HOME,
#    ~/.claude-work, claude-work-memory-global, the cl-w alias) — NOT the
#    substring "work" alone, which also appears in legitimate words this repo
#    uses: workflow, workspace, worktree, network, framework, workaround.
concept_hits=$(git ls-files -z \
  | xargs -0 grep -nEIHi 'claude[_-]work|\bcl-w\b' 2>/dev/null \
  | grep -v '^scripts/check-no-identity.sh:' || true)

if [ -n "$concept_hits" ]; then
  echo "work/personal split leak — these tracked files encode a second work config root:" >&2
  printf '%s\n' "$concept_hits" >&2
  fail=1
else
  echo "ok: no work/personal config-root split"
fi

exit "$fail"
