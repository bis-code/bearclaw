#!/bin/sh
# sessionstart-graphify-nudge.sh — SessionStart hook: nudges (once EVER per
# repo) to run `graphify on` when the current repo looks like code and
# graphify isn't active here yet.
#
# NUDGE, NEVER AUTO-BUILD: graphify's own post-commit rebuild is already
# per-repo opt-in via `git config --local graphify.rebuild` — auto-building a
# graph in every repo a session opens in is a machine-crash risk, so this
# hook only ever prints a one-line suggestion.
#
# Silenced per-repo:                  git config --local graphify.ignore true
# Active per-repo (skips the nudge):  graphify-out/graph.json exists, or
#                                      git config --local graphify.rebuild is true
#
# Throttle: once EVER per repo (not daily — this is "have you tried this",
# not a recurring nag), keyed by a hash of the repo path.
# Seams (tests): GRAPHIFY_NUDGE_REPO, XDG_STATE_HOME, GRAPHIFY_NUDGE_FORCE=1 (skip throttle).
set +e

REPO="${GRAPHIFY_NUDGE_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
# -e, not -d: a git WORKTREE's .git is a plain file, not a directory.
[ -n "$REPO" ] && [ -e "$REPO/.git" ] || exit 0

# (b) looks like code — cheap maxdepth-2 check, no full-tree walk.
looks_like_code=0
for pat in '*.go' '*.ts' '*.py' '*.java' '*.swift'; do
  if [ -n "$(find "$REPO" -maxdepth 2 -name "$pat" 2>/dev/null | head -1)" ]; then
    looks_like_code=1
    break
  fi
done
[ "$looks_like_code" -eq 1 ] || [ -f "$REPO/package.json" ] || [ -f "$REPO/go.mod" ] || exit 0

# (c) already active
[ -f "$REPO/graphify-out/graph.json" ] && exit 0
[ "$(git -C "$REPO" config --local --get graphify.rebuild 2>/dev/null)" = "true" ] && exit 0

# (d) silenced
[ "$(git -C "$REPO" config --local --get graphify.ignore 2>/dev/null)" = "true" ] && exit 0

# (e) once-ever-per-repo throttle
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-graphify"
mkdir -p "$STATE" 2>/dev/null
HASH=$(printf '%s' "$REPO" | cksum | cut -d' ' -f1)
STAMP="$STATE/nudged.$HASH"
if [ "${GRAPHIFY_NUDGE_FORCE:-0}" != "1" ] && [ -f "$STAMP" ]; then
  exit 0
fi
: > "$STAMP" 2>/dev/null

MSG="This repo isn't graphify-enabled — run \`graphify on\` for code-structure queries (query_graph/shortest_path/get_node)."
jq -n --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
