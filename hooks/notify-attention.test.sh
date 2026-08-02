#!/bin/sh
# Tests for notify-attention.sh. Uses CLAUDE_NOTIFY_LOG to capture deliveries
# ("title<TAB>subtitle<TAB>message") instead of popping real macOS notifications.
HOOK="$(dirname "$0")/notify-attention.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/notify.log"
PROJDIR="$TMP/myproj"; mkdir -p "$PROJDIR"
EMPTY="$TMP/empty.jsonl"; : > "$EMPTY"   # exists, no title entries (no find, no name)
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

run(){ printf '%s' "$1" | CLAUDE_NOTIFY_LOG="$LOG" sh "$HOOK"; }

# T1: permission_prompt -> 🔐 marker on message, body preserved
: > "$LOG"
run "$(printf '{"notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"%s"}' "$PROJDIR")" >/dev/null
line=$(tail -1 "$LOG")
[ "$(printf '%s' "$line" | cut -f1)" = "myproj" ] && ok "t1 title=project" || bad "t1 title" "$line"
[ "$(printf '%s' "$line" | cut -f3)" = "🔐 Claude needs your permission to use Bash" ] && ok "t1 approval marker + body" || bad "t1 body" "$line"

# T2: idle_prompt with no message -> default 'Waiting for your input' + ✋
: > "$LOG"
run "$(printf '{"notification_type":"idle_prompt","cwd":"%s"}' "$PROJDIR")" >/dev/null
[ "$(tail -1 "$LOG" | cut -f3)" = "✋ Waiting for your input" ] && ok "t2 idle default message" || bad "t2 default" "$(cat "$LOG")"

# T3: missing cwd -> default title
: > "$LOG"
run '{"notification_type":"idle_prompt","message":"hi"}' >/dev/null
[ "$(tail -1 "$LOG" | cut -f1)" = "Claude Code" ] && ok "t3 default title" || bad "t3 default title" "$(cat "$LOG")"

# T4: empty stdin -> exit 0, no delivery
: > "$LOG"
printf '' | CLAUDE_NOTIFY_LOG="$LOG" sh "$HOOK"; rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$LOG" ] && ok "t4 empty stdin -> exit 0, no delivery" || bad "t4" "rc=$rc log=$(cat "$LOG")"

# T5: injection-safety — message with quotes/backticks/$() flows literally (no eval)
: > "$LOG"
EVIL='"; touch '"$TMP"'/PWNED; echo `id` $(whoami)'
run "$(jq -nc --arg m "$EVIL" --arg c "$PROJDIR" '{notification_type:"permission_prompt",message:$m,cwd:$c}')" >/dev/null
[ ! -e "$TMP/PWNED" ] && ok "t5 no shell injection (PWNED absent)" || bad "t5 injection" "PWNED created"
printf '%s' "$(tail -1 "$LOG" | cut -f3)" | grep -qF 'touch' && ok "t5 message captured literally" || bad "t5 literal" "$(cat "$LOG")"

# T6: session_id present (empty transcript) -> subtitle carries short id ("which chat")
: > "$LOG"
run "$(printf '{"notification_type":"idle_prompt","message":"hi","cwd":"%s","transcript_path":"%s","session_id":"deadbeef-1234-5678-9abc"}' "$PROJDIR" "$EMPTY")" >/dev/null
printf '%s' "$(tail -1 "$LOG" | cut -f2)" | grep -q "#deadbeef" && ok "t6 subtitle has short session id" || bad "t6 sid" "$(cat "$LOG")"

# T7: git repo on a branch -> subtitle carries branch name + session id
G="$TMP/gitproj"; mkdir -p "$G"
( cd "$G" && git init -q && git checkout -q -b feature-x 2>/dev/null; git config user.email t@t; git config user.name t )
: > "$LOG"
printf '{"notification_type":"idle_prompt","message":"hi","cwd":"%s","transcript_path":"%s","session_id":"abc12345-0000"}' "$G" "$EMPTY" | CLAUDE_NOTIFY_LOG="$LOG" sh "$HOOK" >/dev/null
sub=$(tail -1 "$LOG" | cut -f2)
printf '%s' "$sub" | grep -q "feature-x" && ok "t7 subtitle has git branch" || bad "t7 branch" "$sub"
printf '%s' "$sub" | grep -q "#abc12345" && ok "t7 subtitle has short session id" || bad "t7 sid" "$sub"

# T8: transcript with /rename custom-title -> title = that name (preferred over ai-title)
NAMED="$TMP/named.jsonl"
printf '%s\n' '{"type":"ai-title","aiTitle":"old auto title","sessionId":"x"}'      > "$NAMED"
printf '%s\n' '{"type":"custom-title","customTitle":"My Renamed Chat","sessionId":"x"}' >> "$NAMED"
: > "$LOG"
printf '{"notification_type":"idle_prompt","message":"hi","cwd":"%s","transcript_path":"%s","session_id":"feedface-0000"}' "$PROJDIR" "$NAMED" | CLAUDE_NOTIFY_LOG="$LOG" sh "$HOOK" >/dev/null
l=$(tail -1 "$LOG")
[ "$(printf '%s' "$l" | cut -f1)" = "My Renamed Chat" ] && ok "t8 title = /rename custom-title" || bad "t8 title" "$l"
printf '%s' "$(printf '%s' "$l" | cut -f2)" | grep -q "myproj" && ok "t8 subtitle keeps project" || bad "t8 sub" "$l"

# T9: transcript with ai-title only -> title = ai-title (fallback)
AIT="$TMP/ai.jsonl"
printf '%s\n' '{"type":"ai-title","aiTitle":"Auto Topic Title","sessionId":"x"}' > "$AIT"
: > "$LOG"
printf '{"notification_type":"idle_prompt","message":"hi","cwd":"%s","transcript_path":"%s"}' "$PROJDIR" "$AIT" | CLAUDE_NOTIFY_LOG="$LOG" sh "$HOOK" >/dev/null
[ "$(tail -1 "$LOG" | cut -f1)" = "Auto Topic Title" ] && ok "t9 title = ai-title fallback" || bad "t9 title" "$(cat "$LOG")"

# T10: silent types (auth_success, elicitation_*) -> no delivery
for t in auth_success elicitation_dialog elicitation_complete elicitation_response; do
  : > "$LOG"
  run "$(printf '{"notification_type":"%s","message":"x","cwd":"%s"}' "$t" "$PROJDIR")" >/dev/null
  [ ! -s "$LOG" ] && ok "t10 $t silent" || bad "t10 $t" "$(cat "$LOG")"
done

# T11: missing notification_type -> neutral 🔔 fire (never drop a real signal)
: > "$LOG"
run "$(printf '{"message":"Claude needs your attention","cwd":"%s"}' "$PROJDIR")" >/dev/null
[ "$(tail -1 "$LOG" | cut -f3)" = "🔔 Claude needs your attention" ] && ok "t11 unknown type -> neutral fire" || bad "t11 neutral" "$(cat "$LOG")"

# T12: unknown notification_type -> neutral 🔔 fire (forward-compat)
: > "$LOG"
run "$(printf '{"notification_type":"future_kind","message":"hi","cwd":"%s"}' "$PROJDIR")" >/dev/null
[ "$(tail -1 "$LOG" | cut -f3)" = "🔔 hi" ] && ok "t12 future type -> neutral fire" || bad "t12 future" "$(cat "$LOG")"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
