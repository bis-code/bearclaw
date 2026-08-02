#!/bin/sh
# Tests for pretooluse-confirm-gate.sh. Exits non-zero on any failure.
HOOK="$(dirname "$0")/pretooluse-confirm-gate.sh"
fail=0
check() { # $1=desc $2=json_input $3=DENY|PASS
    out=$(printf '%s' "$2" | sh "$HOOK")
    if [ -n "$out" ] && ! printf '%s' "$out" | jq empty 2>/dev/null; then
        echo "FAIL $1 (invalid JSON: $out)"; fail=1; return
    fi
    if [ "$3" = "DENY" ]; then
        dec=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
        [ "$dec" = "deny" ] && echo "ok   $1" || { echo "FAIL $1 (expected deny, got: $out)"; fail=1; }
    else
        [ -z "$out" ] && echo "ok   $1" || { echo "FAIL $1 (expected empty, got: $out)"; fail=1; }
    fi
}
check "bare git push denied"          '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' DENY
check "confirmed prefix passes"       '{"tool_name":"Bash","tool_input":{"command":"CLAUDE_CONFIRMED=1 git push origin main"}}' PASS
check "suffix-confirm bypass denied"  '{"tool_name":"Bash","tool_input":{"command":"git push origin main && CLAUDE_CONFIRMED=1 echo ok"}}' DENY
check "newline command valid json"    '{"tool_name":"Bash","tool_input":{"command":"git push\nrm -rf /tmp/x"}}' DENY
check "echo mentioning git push"      '{"tool_name":"Bash","tool_input":{"command":"echo \"git push is fine\""}}' PASS
check "railway config read passes"    '{"tool_name":"Bash","tool_input":{"command":"cat railway.toml"}}' PASS
check "railway up denied"             '{"tool_name":"Bash","tool_input":{"command":"railway up"}}' DENY
check "gh pr create denied"           '{"tool_name":"Bash","tool_input":{"command":"gh pr create --fill"}}' DENY
check "yarn run deploy denied"        '{"tool_name":"Bash","tool_input":{"command":"yarn run deploy"}}' DENY
check "ls passes"                     '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' PASS
check "non-bash tool passes"          '{"tool_name":"Read","tool_input":{"command":"git push"}}' PASS
check "psql DROP DATABASE denied"     '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP DATABASE prod\""}}' DENY
check "psql lowercase drop denied"    '{"tool_name":"Bash","tool_input":{"command":"psql -d app -c \"drop table users\""}}' DENY
check "mysql TRUNCATE denied"         '{"tool_name":"Bash","tool_input":{"command":"mysql -e \"TRUNCATE TABLE sessions\""}}' DENY
check "psql plain SELECT passes"      '{"tool_name":"Bash","tool_input":{"command":"psql -c \"SELECT count(*) FROM users\""}}' PASS
check "echo mentioning DROP passes"   '{"tool_name":"Bash","tool_input":{"command":"echo \"how to DROP TABLE in psql\""}}' PASS
check "commit --no-verify denied"     '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' DENY
check "push --no-verify denied"       '{"tool_name":"Bash","tool_input":{"command":"git push --no-verify"}}' DENY
check "confirmed --no-verify passes"  '{"tool_name":"Bash","tool_input":{"command":"CLAUDE_CONFIRMED=1 git commit --no-verify -m x"}}' PASS
check "commit -n denied"              '{"tool_name":"Bash","tool_input":{"command":"git commit -n -m x"}}' DENY
check "no-verify flag after -m denied" '{"tool_name":"Bash","tool_input":{"command":"git commit -m msg --no-verify"}}' DENY
check "echo no-verify passes"         '{"tool_name":"Bash","tool_input":{"command":"echo \"use --no-verify\""}}' PASS
check "commit msg mentioning flag ok" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: gate --no-verify in hook\""}}' PASS
check "commit -m single-quote flag ok" '{"tool_name":"Bash","tool_input":{"command":"git commit -m '"'"'add --no-verify gate'"'"'"}}' PASS
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
