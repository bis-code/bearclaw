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

run(){ CLAUDE_SETUP_REPO="$R" CLAUDE_CONFIG_DIR="$TMP/root-$1" XDG_STATE_HOME="$TMP/state-$1" DRIFT_FORCE="${2:-1}" sh "$DIR/sessionstart-config-drift.sh"; }

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

# Clean/sync the fixture repo before the staleness tests below, so only the
# staleness check's own behaviour is under test (no leftover dirty/unpushed
# state from t2-t5 bleeding in).
( cd "$R" && git add -A && git commit -qm "cleanup for staleness tests" >/dev/null 2>&1
  git push -q origin HEAD 2>/dev/null )
HEAD_SHA=$(git -C "$R" rev-parse HEAD)

# t6: installed copy stale (sha in .installed-from differs from repo HEAD) ->
# emits the staleness line
mkdir -p "$TMP/root-t6"
printf 'repo=%s\nsha=%s\n' "$R" "0000000000000000000000000000000000000000" > "$TMP/root-t6/.installed-from"
out=$(CLAUDE_SETUP_REPO="$R" CLAUDE_CONFIG_DIR="$TMP/root-t6" XDG_STATE_HOME="$TMP/state-t6" DRIFT_FORCE=1 sh "$DIR/sessionstart-config-drift.sh")
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' | grep -q "repo is ahead of the installed copy — run install.sh" \
  && ok "t6 stale sha: nudges" || bad "t6" "$out"

# t7: installed copy matches repo HEAD -> silent
mkdir -p "$TMP/root-t7"
printf 'repo=%s\nsha=%s\n' "$R" "$HEAD_SHA" > "$TMP/root-t7/.installed-from"
out=$(CLAUDE_SETUP_REPO="$R" CLAUDE_CONFIG_DIR="$TMP/root-t7" XDG_STATE_HOME="$TMP/state-t7" DRIFT_FORCE=1 sh "$DIR/sessionstart-config-drift.sh")
[ -z "$out" ] && ok "t7 sha matches: silent" || bad "t7" "$out"

# t8: staleness check has its OWN once-daily throttle, independent of the
# dirty/unpushed check's stamp
mkdir -p "$TMP/root-t8"
printf 'repo=%s\nsha=%s\n' "$R" "0000000000000000000000000000000000000000" > "$TMP/root-t8/.installed-from"
CLAUDE_SETUP_REPO="$R" CLAUDE_CONFIG_DIR="$TMP/root-t8" XDG_STATE_HOME="$TMP/state-t8" DRIFT_FORCE=0 sh "$DIR/sessionstart-config-drift.sh" >/dev/null
out=$(CLAUDE_SETUP_REPO="$R" CLAUDE_CONFIG_DIR="$TMP/root-t8" XDG_STATE_HOME="$TMP/state-t8" DRIFT_FORCE=0 sh "$DIR/sessionstart-config-drift.sh")
[ -z "$out" ] && ok "t8 staleness throttle holds on second same-day run" || bad "t8" "$out"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
