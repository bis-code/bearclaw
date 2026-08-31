#!/bin/sh
# Tests for sessionstart-graphify-nudge.sh — code-repo detection, active/
# silenced skip, and the once-ever-per-repo throttle.
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "ok   $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL $1 ($2)"; FAIL=$((FAIL+1)); }

git_repo() { # <dir>
  mkdir -p "$1" && ( cd "$1" && git init -q && git config user.email t@t && git config user.name t )
}

run(){ # <repo> <state-dir> [force]
  GRAPHIFY_NUDGE_REPO="$1" XDG_STATE_HOME="$2" GRAPHIFY_NUDGE_FORCE="${3:-1}" sh "$DIR/sessionstart-graphify-nudge.sh"
}

# t1: not a code repo (no matching files) -> silent
R1="$TMP/plain"; git_repo "$R1" >/dev/null; echo hi > "$R1/README.md"
out=$(run "$R1" "$TMP/state-t1")
[ -z "$out" ] && ok "t1 non-code repo: silent" || bad "t1" "$out"

# t2: fresh code repo, graphify inactive -> nudges once
R2="$TMP/code"; git_repo "$R2" >/dev/null; echo 'package main' > "$R2/main.go"
out=$(run "$R2" "$TMP/state-t2")
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "graphify on" && ok "t2 fresh code repo: nudges" || bad "t2" "$out"

# t3: throttle — second run on the same repo (no force) is silent
XDG_STATE_HOME="$TMP/state-t3" GRAPHIFY_NUDGE_REPO="$R2" GRAPHIFY_NUDGE_FORCE=0 sh "$DIR/sessionstart-graphify-nudge.sh" >/dev/null
out=$(XDG_STATE_HOME="$TMP/state-t3" GRAPHIFY_NUDGE_REPO="$R2" GRAPHIFY_NUDGE_FORCE=0 sh "$DIR/sessionstart-graphify-nudge.sh")
[ -z "$out" ] && ok "t3 once-ever throttle holds" || bad "t3" "$out"

# t4: graphify-out/graph.json present -> silent (already active)
R4="$TMP/active"; git_repo "$R4" >/dev/null; mkdir -p "$R4/graphify-out"
echo 'package main' > "$R4/main.go"; echo '{}' > "$R4/graphify-out/graph.json"
out=$(run "$R4" "$TMP/state-t4")
[ -z "$out" ] && ok "t4 graph.json present: silent" || bad "t4" "$out"

# t5: graphify.rebuild=true -> silent (active via opt-in, no graph.json needed)
R5="$TMP/rebuild"; git_repo "$R5" >/dev/null; ( cd "$R5" && git config --local graphify.rebuild true )
echo 'package main' > "$R5/main.go"
out=$(run "$R5" "$TMP/state-t5")
[ -z "$out" ] && ok "t5 graphify.rebuild=true: silent" || bad "t5" "$out"

# t6: graphify.ignore=true -> silent (silenced)
R6="$TMP/ignored"; git_repo "$R6" >/dev/null; ( cd "$R6" && git config --local graphify.ignore true )
echo 'package main' > "$R6/main.go"
out=$(run "$R6" "$TMP/state-t6")
[ -z "$out" ] && ok "t6 graphify.ignore=true: silent" || bad "t6" "$out"

# t7: not inside a git repo at all -> silent
R7="$TMP/notgit"; mkdir -p "$R7"; echo 'package main' > "$R7/main.go"
out=$(run "$R7" "$TMP/state-t7")
[ -z "$out" ] && ok "t7 not a git repo: silent" || bad "t7" "$out"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
