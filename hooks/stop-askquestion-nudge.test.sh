#!/bin/sh
# Tests for stop-askquestion-nudge.sh. Builds a minimal transcript whose last
# assistant message is the text under test, then asserts whether the hook blocks.
HOOK="$(dirname "$0")/stop-askquestion-nudge.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

# Build a transcript with one assistant text message = $1 ('\n' -> real newline,
# matching how real transcript text blocks store multi-line replies). Returns path.
mk(){
  txt=$(printf '%b' "$1")
  f="$TMP/$2.jsonl"
  jq -nc --arg t "$txt" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$f"
  printf '%s' "$f"
}

# Run hook against transcript $1 with session id $2. Echoes the JSON output.
run(){
  printf '{"session_id":"%s","transcript_path":"%s"}' "$2" "$1" \
    | CLAUDE_ASKQ_STATE_DIR="$STATE" sh "$HOOK"
}

blocks(){ printf '%s' "$1" | jq -e '.decision == "block"' >/dev/null 2>&1; }

# T1: prose "Option A / Option B" -> blocks
t=$(mk "Here are two ways forward. Option A: do X. Option B: do Y. Which do you prefer?" t1)
out=$(run "$t" s1)
blocks "$out" && ok "t1 Option A/B prose blocks" || bad "t1" "$out"

# T2: numbered options + question + cue -> blocks
rm -f "$STATE"/*
t=$(mk "How should I proceed?\n1) Rewrite the hook\n2) Patch it in place\nWhich one?" t2)
out=$(run "$t" s2)
blocks "$out" && ok "t2 numbered+cue blocks" || bad "t2" "$out"

# T3: plain prose answer, no options -> no block
rm -f "$STATE"/*
t=$(mk "Done. I rewrote the hook and all tests pass. Want me to commit it?" t3)
out=$(run "$t" s3)
blocks "$out" && bad "t3 plain answer must not block" "$out" || ok "t3 plain answer passes"

# T4: numbered list WITHOUT a choice cue/question -> no block (e.g. a changelog)
rm -f "$STATE"/*
t=$(mk "Changes made:\n1. Added notification_type branching.\n2. Added custom-icon support." t4)
out=$(run "$t" s4)
blocks "$out" && bad "t4 plain list must not block" "$out" || ok "t4 plain list passes"

# T5: once per session — first blocks, second (same session) passes
rm -f "$STATE"/*
t=$(mk "Option A: x. Option B: y. Which?" t5)
out1=$(run "$t" s5); out2=$(run "$t" s5)
{ blocks "$out1" && ! blocks "$out2"; } && ok "t5 blocks once per session" || bad "t5" "1=$out1 2=$out2"

# T6: stop_hook_active=true -> never block (loop guard)
rm -f "$STATE"/*
t=$(mk "Option A: x. Option B: y. Which?" t6)
out=$(printf '{"session_id":"s6","transcript_path":"%s","stop_hook_active":true}' "$t" \
  | CLAUDE_ASKQ_STATE_DIR="$STATE" sh "$HOOK")
blocks "$out" && bad "t6 stop_hook_active must not block" "$out" || ok "t6 loop guard passes"

# T7: missing transcript -> exit 0, no output
rm -f "$STATE"/*
out=$(printf '{"session_id":"s7","transcript_path":"%s/nope.jsonl"}' "$TMP" \
  | CLAUDE_ASKQ_STATE_DIR="$STATE" sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "t7 missing transcript -> silent exit 0" || bad "t7" "rc=$rc out=$out"

# T8: turn that asked via tool_use (no assistant text) -> no block
rm -f "$STATE"/*
f="$TMP/t8.jsonl"
jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"AskUserQuestion",input:{}}]}}' > "$f"
out=$(run "$f" s8)
blocks "$out" && bad "t8 tool_use turn must not block" "$out" || ok "t8 tool_use turn passes"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
