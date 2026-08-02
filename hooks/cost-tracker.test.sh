#!/bin/sh
# Tests for cost-tracker.sh. Runs the worker SYNCHRONOUSLY (CLAUDE_COST_TRACKER_SYNC=1)
# into a temp metrics dir (CLAUDE_METRICS_DIR) so assertions are deterministic.
HOOK="$(dirname "$0")/cost-tracker.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
M="$TMP/metrics"
PROJDIR="$TMP/myproj"; mkdir -p "$PROJDIR"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

# Build a transcript with two assistant turns + a non-assistant line + a malformed line.
TR="$TMP/t.jsonl"
write_turn1() {
  {
    printf '%s\n' '{"type":"user","message":{"role":"user"}}'
    printf '%s\n' 'THIS IS NOT JSON {{{'
    printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000}}}'
  } > "$TR"
}
write_turn2() {  # append a second assistant turn (cumulative grows)
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000}}}' >> "$TR"
}
run() { # $1 = json payload
  printf '%s' "$1" | CLAUDE_COST_TRACKER_SYNC=1 CLAUDE_METRICS_DIR="$M" sh "$HOOK"
}
payload() { printf '{"session_id":"sess1","transcript_path":"%s","cwd":"%s"}' "$TR" "$PROJDIR"; }

# --- Test 1: first turn writes one delta row with correct fields ---
rm -rf "$M"; write_turn1
run "$(payload)" >/dev/null
ROW=$(tail -1 "$M/costs.jsonl" 2>/dev/null)
[ -n "$ROW" ] && printf '%s' "$ROW" | jq empty 2>/dev/null && ok "t1 row is valid JSON" || bad "t1 row valid JSON" "$ROW"
[ "$(printf '%s' "$ROW" | jq -r '.input_tokens')"  = "1000" ] && ok "t1 input=1000" || bad "t1 input" "$ROW"
[ "$(printf '%s' "$ROW" | jq -r '.output_tokens')" = "500" ]  && ok "t1 output=500" || bad "t1 output" "$ROW"
[ "$(printf '%s' "$ROW" | jq -r '.cache_read_tokens')" = "2000" ] && ok "t1 cacheRead=2000" || bad "t1 cacheRead" "$ROW"
[ "$(printf '%s' "$ROW" | jq -r '.project')" = "myproj" ] && ok "t1 project=myproj" || bad "t1 project" "$ROW"
[ "$(printf '%s' "$ROW" | jq -r '.model')" = "claude-sonnet-4-6" ] && ok "t1 model" || bad "t1 model" "$ROW"
# cost: (1000*3 + 500*15 + 0 + 2000*0.30)/1e6 = 0.0111
[ "$(printf '%s' "$ROW" | jq -r '.estimated_cost_usd')" = "0.0111" ] && ok "t1 cost=0.0111" || bad "t1 cost" "$ROW"

# --- Test 2: second turn writes a DELTA row (not cumulative) ---
write_turn2
run "$(payload)" >/dev/null
ROW2=$(tail -1 "$M/costs.jsonl")
[ "$(printf '%s' "$ROW2" | jq -r '.input_tokens')" = "1000" ] && ok "t2 delta input=1000 (not 2000)" || bad "t2 delta" "$ROW2"
[ "$(wc -l < "$M/costs.jsonl" | tr -d ' ')" = "2" ] && ok "t2 two rows total" || bad "t2 row count" "$(cat "$M/costs.jsonl")"

# --- Test 3: no new tokens (same transcript) -> no extra row ---
run "$(payload)" >/dev/null
[ "$(wc -l < "$M/costs.jsonl" | tr -d ' ')" = "2" ] && ok "t3 no-delta -> no row" || bad "t3 no-delta" "$(cat "$M/costs.jsonl")"

# --- Test 4: opus tier rates ---
rm -rf "$M"; TRO="$TMP/o.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' > "$TRO"
printf '{"session_id":"s2","transcript_path":"%s","cwd":"%s"}' "$TRO" "$PROJDIR" | CLAUDE_COST_TRACKER_SYNC=1 CLAUDE_METRICS_DIR="$M" sh "$HOOK" >/dev/null
[ "$(jq -r '.estimated_cost_usd' "$M/costs.jsonl")" = "15" ] && ok "t4 opus 1M input = \$15" || bad "t4 opus cost" "$(cat "$M/costs.jsonl")"

# --- Test 5: missing transcript -> exit 0, no row, no crash ---
rm -rf "$M"
printf '{"session_id":"s3","transcript_path":"%s/nope.jsonl","cwd":"%s"}' "$TMP" "$PROJDIR" | CLAUDE_COST_TRACKER_SYNC=1 CLAUDE_METRICS_DIR="$M" sh "$HOOK" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$M/costs.jsonl" ] && ok "t5 missing transcript -> no row, exit 0" || bad "t5 missing transcript" "exit=$rc"

# --- Test 6: empty/no-usage transcript -> no row ---
rm -rf "$M"; TRE="$TMP/e.jsonl"; printf '%s\n' '{"type":"user","message":{}}' > "$TRE"
printf '{"session_id":"s4","transcript_path":"%s","cwd":"%s"}' "$TRE" "$PROJDIR" | CLAUDE_COST_TRACKER_SYNC=1 CLAUDE_METRICS_DIR="$M" sh "$HOOK" >/dev/null
[ ! -f "$M/costs.jsonl" ] && ok "t6 no usage -> no row" || bad "t6 no usage" "$(cat "$M/costs.jsonl" 2>/dev/null)"

# --- Test 7: append failure -> error marker + log written ---
rm -rf "$M"; mkdir -p "$M"; mkdir "$M/costs.jsonl"   # make append target a dir -> >> fails
write_turn1
printf '{"session_id":"s5","transcript_path":"%s","cwd":"%s"}' "$TR" "$PROJDIR" | CLAUDE_COST_TRACKER_SYNC=1 CLAUDE_METRICS_DIR="$M" sh "$HOOK" >/dev/null 2>&1
[ -f "$M/.cost-tracker.error" ] && ok "t7 failure writes error marker" || bad "t7 error marker" "missing"
[ -s "$M/cost-tracker.log" ] && ok "t7 failure appends to log" || bad "t7 log" "missing/empty"
rmdir "$M/costs.jsonl" 2>/dev/null

# --- Test 8: pending error marker -> hook emits systemMessage then clears it ---
rm -rf "$M"; mkdir -p "$M"; printf '2026-06-03T10:00:00+0300\tboom\n' > "$M/.cost-tracker.error"
OUT=$(printf '{"session_id":"s6","transcript_path":"%s/none.jsonl","cwd":"%s"}' "$TMP" "$PROJDIR" | CLAUDE_COST_TRACKER_SYNC=1 CLAUDE_METRICS_DIR="$M" sh "$HOOK")
printf '%s' "$OUT" | jq -e '.systemMessage | test("cost-tracker")' >/dev/null 2>&1 && ok "t8 surfaces prior error" || bad "t8 surface" "$OUT"
[ ! -f "$M/.cost-tracker.error" ] && ok "t8 clears marker after surfacing" || bad "t8 clear" "still present"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
