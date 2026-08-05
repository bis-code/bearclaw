#!/bin/sh
# Tests for userpromptsubmit-deepthink-nudge.sh. CLAUDE_NUDGE_STATE_DIR seam
# keeps the once-per-session markers in a temp dir.
HOOK="$(dirname "$0")/userpromptsubmit-deepthink-nudge.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
INSTALLED="$TMP/installed_plugins.json"; printf '{"deep-think@bis-code":{"version":"1.0.0"}}\n' > "$INSTALLED"
MISSING="$TMP/no-deepthink.json"; printf '{"other-plugin@bis-code":{"version":"1.0.0"}}\n' > "$MISSING"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }
run(){ printf '%s' "$1" | CLAUDE_NUDGE_STATE_DIR="$TMP" DEEPTHINK_PLUGINS_FILE="$INSTALLED" sh "$HOOK"; }

# t1: architecture trigger -> additionalContext emitted, names deep-think
out=$(run '{"prompt":"let us make an architecture decision for the payment flow","session_id":"s1"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && ok "t1 nudge emitted" || bad "t1 emit" "$out"
printf '%s' "$out" | grep -q 'deep-think' && ok "t1 names deep-think" || bad "t1 name" "$out"

# t2: same session, second matching prompt -> silent (once per session)
out=$(run '{"prompt":"another architecture question","session_id":"s1"}')
[ -z "$out" ] && ok "t2 once per session" || bad "t2" "$out"

# t3: new session -> fires again
out=$(run '{"prompt":"schema design for trips","session_id":"s2"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput' >/dev/null 2>&1 && ok "t3 new session fires" || bad "t3" "$out"

# t4: non-matching prompt -> silent
out=$(run '{"prompt":"fix the typo in the readme","session_id":"s3"}')
[ -z "$out" ] && ok "t4 non-trigger silent" || bad "t4" "$out"

# t5: empty stdin -> exit 0, silent
out=$(printf '' | CLAUDE_NUDGE_STATE_DIR="$TMP" sh "$HOOK"); rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } && ok "t5 empty stdin no-op" || bad "t5" "rc=$rc out=$out"

# t6: plugins file exists but lacks the deep-think key -> silent even on a matching prompt
mkdir -p "$TMP/s6"
out=$(printf '%s' '{"prompt":"architecture decision for the auth flow","session_id":"absent1"}' \
  | CLAUDE_NUDGE_STATE_DIR="$TMP/s6" DEEPTHINK_PLUGINS_FILE="$MISSING" sh "$HOOK")
[ -z "$out" ] && ok "t6 silent when plugin key absent" || bad "t6" "$out"

# t7: plugins file path doesn't exist -> silent
mkdir -p "$TMP/s7"
out=$(printf '%s' '{"prompt":"architecture decision for the auth flow","session_id":"absent2"}' \
  | CLAUDE_NUDGE_STATE_DIR="$TMP/s7" DEEPTHINK_PLUGINS_FILE="$TMP/s7/nope.json" sh "$HOOK")
[ -z "$out" ] && ok "t7 silent when plugins file missing" || bad "t7" "$out"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
