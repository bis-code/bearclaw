#!/bin/sh
# Tests for pretooluse-verification-pair.sh. CLAUDE_PAIR_STATE_DIR seam.
HOOK="$(dirname "$0")/pretooluse-verification-pair.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }
run(){ printf '%s' "$1" | CLAUDE_PAIR_STATE_DIR="$TMP" sh "$HOOK"; }
sk(){ printf '{"tool_name":"Skill","tool_input":{"skill":"%s"},"session_id":"%s"}' "$1" "$2"; }

# t1: finishing WITHOUT verification -> deny, names the pair
out=$(run "$(sk superpowers:finishing-a-development-branch s1)")
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1 && ok "t1 unpaired finish denied" || bad "t1" "$out"
printf '%s' "$out" | grep -q 'verification-before-completion' && ok "t1 names the pair" || bad "t1 pair" "$out"

# t2: re-issue, same session -> allowed (speed bump spent)
out=$(run "$(sk superpowers:finishing-a-development-branch s1)")
[ -z "$out" ] && ok "t2 re-issue passes" || bad "t2" "$out"

# t3: fresh session, verification FIRST then finishing -> both allowed
out=$(run "$(sk superpowers:verification-before-completion s3)")
[ -z "$out" ] && ok "t3 verification allowed" || bad "t3" "$out"
out=$(run "$(sk superpowers:finishing-a-development-branch s3)")
[ -z "$out" ] && ok "t3 paired finish allowed" || bad "t3 finish" "$out"

# t4: unrelated skill -> ignored
out=$(run "$(sk handoff s4)")
[ -z "$out" ] && ok "t4 other skills ignored" || bad "t4" "$out"

# t5: bare names (no superpowers: prefix) also work
out=$(run "$(sk verification-before-completion s5)")
out=$(run "$(sk finishing-a-development-branch s5)")
[ -z "$out" ] && ok "t5 bare names paired" || bad "t5" "$out"

# t6: non-Skill tools ignored
out=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s6"}' | CLAUDE_PAIR_STATE_DIR="$TMP" sh "$HOOK")
[ -z "$out" ] && ok "t6 non-skill ignored" || bad "t6" "$out"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
