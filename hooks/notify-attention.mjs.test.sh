#!/bin/sh
# W6 equivalence tests: notify-attention.mjs must produce byte-identical
# CLAUDE_NOTIFY_LOG lines to the authoritative notify-attention.sh across the
# fixture matrix. Cutover happens only while this stays green.
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
command -v node >/dev/null 2>&1 || { echo "skip: node not installed"; exit 0; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "ok   $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL $1 ($2)"; FAIL=$((FAIL+1)); }

# fixture git repo for the branch field
WS="$TMP/ws"; mkdir -p "$WS"
( cd "$WS" && git init -q -b fixture-branch && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m x )

run_pair(){ # $1 label, $2 json
  SH="$TMP/sh-$1.log"; MJ="$TMP/mjs-$1.log"
  printf '%s' "$2" | CLAUDE_NOTIFY_LOG="$SH" sh "$DIR/notify-attention.sh"
  printf '%s' "$2" | CLAUDE_NOTIFY_LOG="$MJ" node "$DIR/notify-attention.mjs"
  if diff -q "$SH" "$MJ" >/dev/null 2>&1; then ok "$1 equivalent"
  else bad "$1" "sh=[$(cat "$SH" 2>/dev/null)] mjs=[$(cat "$MJ" 2>/dev/null)]"; fi
}

run_pair idle "{\"notification_type\":\"idle_prompt\",\"cwd\":\"$WS\",\"session_id\":\"abcdef1234567890\"}"
run_pair permission "{\"notification_type\":\"permission_prompt\",\"message\":\"custom approval text\",\"cwd\":\"$WS\"}"
run_pair unknown "{\"notification_type\":\"weird_new_type\",\"cwd\":\"$WS\"}"
run_pair no-cwd '{"notification_type":"idle_prompt"}'

# silent types: both must write NOTHING
for t in auth_success elicitation_dialog; do
  SH="$TMP/sh-sil.log"; MJ="$TMP/mjs-sil.log"; rm -f "$SH" "$MJ"
  printf '{"notification_type":"%s"}' "$t" | CLAUDE_NOTIFY_LOG="$SH" sh "$DIR/notify-attention.sh"
  printf '{"notification_type":"%s"}' "$t" | CLAUDE_NOTIFY_LOG="$MJ" node "$DIR/notify-attention.mjs"
  [ ! -s "$SH" ] && [ ! -s "$MJ" ] && ok "silent:$t both silent" || bad "silent:$t" "sh=$(cat "$SH" 2>/dev/null) mjs=$(cat "$MJ" 2>/dev/null)"
done

# malformed stdin: both exit 0, no log
printf 'not json' | CLAUDE_NOTIFY_LOG="$TMP/x1" sh "$DIR/notify-attention.sh"; r1=$?
printf 'not json' | CLAUDE_NOTIFY_LOG="$TMP/x2" node "$DIR/notify-attention.mjs"; r2=$?
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && ok "malformed stdin: both exit 0" || bad "malformed" "rc sh=$r1 mjs=$r2"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
