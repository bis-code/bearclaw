#!/bin/sh
# Tests for pretooluse-dispatch-gate.sh. CLAUDE_DISPATCH_STATE_DIR seam keeps
# per-session markers in a temp dir.
HOOK="$(dirname "$0")/pretooluse-dispatch-gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }
run(){ printf '%s' "$1" | CLAUDE_DISPATCH_STATE_DIR="$TMP" sh "$HOOK"; }

# t1: named agent + model set -> silent allow
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"language-reviewer","model":"sonnet","prompt":"review the diff"},"session_id":"s1"}')
[ -z "$out" ] && ok "t1 named agent silent" || bad "t1" "$out"

# t2: general-purpose + build-failure trigger -> deny naming build-error-resolver
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"the docker build failed with a compile error, fix it"},"session_id":"s2"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1 && ok "t2 gp+trigger denied" || bad "t2" "$out"
printf '%s' "$out" | grep -q 'build-error-resolver' && ok "t2 names agent" || bad "t2 name" "$out"

# t3: SAME suggestion again, same session -> allowed (speed bump, not wall)
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"the docker build failed with a compile error, fix it"},"session_id":"s2"}')
[ -z "$out" ] && ok "t3 re-issue passes" || bad "t3" "$out"

# t4: general-purpose + unmatched prompt -> allowed
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"summarize the latest research on vector databases"},"session_id":"s4"}')
[ -z "$out" ] && ok "t4 legit fallback allowed" || bad "t4" "$out"

# t5: missing model on a NAMED dispatch -> allow + advisory additionalContext
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"architect-reviewer","prompt":"assess the module boundaries"},"session_id":"s5"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="allow"' >/dev/null 2>&1 && ok "t5 model advisory allows" || bad "t5" "$out"
printf '%s' "$out" | grep -q 'model-selection' && ok "t5 advisory text" || bad "t5 text" "$out"

# t6: second missing-model in same session -> silent (once per session)
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"architect-reviewer","prompt":"another boundary check"},"session_id":"s5"}')
[ -z "$out" ] && ok "t6 model advisory once" || bad "t6" "$out"

# t7: empty subagent_type (defaults to general-purpose) + trigger -> denied
out=$(run '{"tool_name":"Task","tool_input":{"model":"sonnet","prompt":"there is a flaky test behaving wrong at runtime"},"session_id":"s7"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1 && ok "t7 unset type gated" || bad "t7" "$out"
printf '%s' "$out" | grep -q 'incident-debugger' && ok "t7 names incident-debugger" || bad "t7 name" "$out"

# t8: other tools -> exit silently
out=$(run '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s8"}')
[ -z "$out" ] && ok "t8 non-dispatch ignored" || bad "t8" "$out"

# t9: deny reason includes the re-issue escape instruction
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"please do a security review of the auth change"},"session_id":"s9"}')
printf '%s' "$out" | grep -q 're-issue' && ok "t9 escape documented" || bad "t9" "$out"

# t10: different trigger after a deny in same session -> still denies (per-suggestion, not per-session)
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"review the diff for correctness"},"session_id":"s9"}')
printf '%s' "$out" | grep -q 'code-review' && ok "t10 per-suggestion tracking" || bad "t10" "$out"

# t11: retired-agent trigger -> alt suggestion names the replacement skill (S6)
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"do an owasp vulnerability audit of the service"},"session_id":"s11"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1 && ok "t11 retired trigger denied" || bad "t11" "$out"
printf '%s' "$out" | grep -q 'security-review skill' && ok "t11 names replacement skill" || bad "t11 name" "$out"

# t12: language-review trigger -> names the merged language-reviewer
out=$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"do a python code review of the changed service"},"session_id":"s12"}')
printf '%s' "$out" | grep -q 'language-reviewer' && ok "t12 names language-reviewer" || bad "t12" "$out"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
