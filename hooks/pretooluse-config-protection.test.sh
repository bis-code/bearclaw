#!/bin/sh
# Tests for pretooluse-config-protection.sh. ASK = permissionDecision ask, PASS = empty.
HOOK="$(dirname "$0")/pretooluse-config-protection.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
touch "$TMP/.eslintrc.json" "$TMP/biome.json" "$TMP/.golangci.yml" "$TMP/app.go" "$TMP/README.md"
fail=0
check() { # $1=desc $2=json_input $3=ASK|PASS
    out=$(printf '%s' "$2" | sh "$HOOK")
    if [ -n "$out" ] && ! printf '%s' "$out" | jq empty 2>/dev/null; then
        echo "FAIL $1 (invalid JSON: $out)"; fail=1; return
    fi
    if [ "$3" = "ASK" ]; then
        d=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
        [ "$d" = "ask" ] && echo "ok   $1" || { echo "FAIL $1 (expected ask, got: $out)"; fail=1; }
    else
        [ -z "$out" ] && echo "ok   $1" || { echo "FAIL $1 (expected empty, got: $out)"; fail=1; }
    fi
}
check "edit existing eslintrc asks"   "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/.eslintrc.json\"}}" ASK
check "write existing biome asks"      "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/biome.json\"}}" ASK
check "edit existing golangci asks"    "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/.golangci.yml\"}}" ASK
check "new (absent) eslintrc passes"   "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/sub/.eslintrc.json\"}}" PASS
check "edit app.go passes"             "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/app.go\"}}" PASS
check "edit README passes"             "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/README.md\"}}" PASS
check "non-edit tool passes"           "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm $TMP/biome.json\"}}" PASS
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
