#!/bin/sh
# Tests for sessionstart-config-drift.sh — drift detection + once-daily throttle.
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "ok   $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL $1 ($2)"; FAIL=$((FAIL+1)); }

# Fixture repo with a synced-surface file + an upstream to be ahead of.
R="$TMP/repo"; mkdir -p "$R/memory-global" "$R/rules"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && echo x > memory-global/MEMORY.md && echo '{}' > settings.json && echo r > rules/a.md \
  && git add -A && git commit -qm init )
( cd "$TMP" && git clone -q --bare "$R" up.git )
( cd "$R" && git remote add origin "$TMP/up.git" && git fetch -q origin && git branch -q --set-upstream-to=origin/master 2>/dev/null || git branch -q --set-upstream-to=origin/main )

run(){ CLAUDE_SETUP_REPO="$R" XDG_STATE_HOME="$TMP/state-$1" DRIFT_FORCE="${2:-1}" sh "$DIR/sessionstart-config-drift.sh"; }

# t1: clean + in sync -> silent
out=$(run t1)
[ -z "$out" ] && ok "t1 clean+synced: silent" || bad "t1" "$out"

# t2: uncommitted synced-surface change -> nudge with count + filename
echo drift >> "$R/memory-global/MEMORY.md"
out=$(run t2)
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "uncommitted" && ok "t2 dirty: nudges" || bad "t2" "$out"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "MEMORY.md" && ok "t2 names the file" || bad "t2f" "$out"

# t3: committed but unpushed -> nudge mentions unpushed
( cd "$R" && git add -A && git commit -qm drift )
out=$(run t3)
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "unpushed" && ok "t3 ahead: nudges unpushed" || bad "t3" "$out"

# t4: throttle — second run same day (DRIFT_FORCE off) is silent
XDG_STATE_HOME="$TMP/state-t4" CLAUDE_SETUP_REPO="$R" DRIFT_FORCE=0 sh "$DIR/sessionstart-config-drift.sh" >/dev/null
out=$(XDG_STATE_HOME="$TMP/state-t4" CLAUDE_SETUP_REPO="$R" DRIFT_FORCE=0 sh "$DIR/sessionstart-config-drift.sh")
[ -z "$out" ] && ok "t4 once-daily throttle holds" || bad "t4" "$out"

# t5: non-synced-surface dirt (e.g. hooks/) does NOT nudge
( cd "$R" && git push -q origin HEAD 2>/dev/null )
mkdir -p "$R/hooks" && echo h > "$R/hooks/x.sh"
out=$(run t5)
[ -z "$out" ] && ok "t5 non-synced dirt ignored (untracked hooks/ file)" || bad "t5" "$out"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
