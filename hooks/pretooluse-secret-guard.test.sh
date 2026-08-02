#!/bin/sh
# Tests for pretooluse-secret-guard.sh. Advisory: WARN = systemMessage present, PASS = empty. Exits non-zero on failure.
HOOK="$(dirname "$0")/pretooluse-secret-guard.sh"
fail=0
check() { # $1=desc $2=json_input $3=WARN|PASS
    out=$(printf '%s' "$2" | sh "$HOOK")
    if [ -n "$out" ] && ! printf '%s' "$out" | jq empty 2>/dev/null; then
        echo "FAIL $1 (invalid JSON: $out)"; fail=1; return
    fi
    if [ "$3" = "WARN" ]; then
        m=$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)
        [ -n "$m" ] && echo "ok   $1" || { echo "FAIL $1 (expected systemMessage, got: $out)"; fail=1; }
    else
        [ -z "$out" ] && echo "ok   $1" || { echo "FAIL $1 (expected empty, got: $out)"; fail=1; }
    fi
}
check "cat .env warns"            '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' WARN
check "cat .env.dev warns"        '{"tool_name":"Bash","tool_input":{"command":"cat config/.env.local"}}' WARN
check "cat credentials.json warns" '{"tool_name":"Bash","tool_input":{"command":"cat secrets/credentials.json"}}' WARN
check "cat token.json warns"      '{"tool_name":"Bash","tool_input":{"command":"cat token.json"}}' WARN
check "0x key literal warns"      '{"tool_name":"Bash","tool_input":{"command":"export PK=0xabc123def4567890abc123def4567890abc123def4567890"}}' WARN
check "64-hex literal warns"      '{"tool_name":"Bash","tool_input":{"command":"echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' WARN
check "cat README passes"         '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}' PASS
check "git status passes"         '{"tool_name":"Bash","tool_input":{"command":"git status"}}' PASS
check "ls passes"                 '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' PASS
check "non-bash tool passes"      '{"tool_name":"Read","tool_input":{"command":"cat .env"}}' PASS
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
