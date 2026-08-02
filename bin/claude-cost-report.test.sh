#!/bin/sh
# Tests for claude-cost-report against a fixture costs.jsonl in a temp metrics dir.
BIN="$(dirname "$0")/claude-cost-report"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
M="$TMP/metrics"; mkdir -p "$M"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

TODAY=$(date +%F)
Y=$(date -v-1d +%F 2>/dev/null || date -d '1 day ago' +%F)
OLD=$(date -v-30d +%F 2>/dev/null || date -d '30 days ago' +%F)

# Fixture: today (2 rows, 2 projects), yesterday (1), 30d-ago (1, outside 7d window).
{
  printf '{"timestamp":"%sT09:00:00+0000","session_id":"a","project":"alpha","model":"claude-sonnet-4-6","input_tokens":1000,"output_tokens":0,"cache_write_tokens":0,"cache_read_tokens":0,"estimated_cost_usd":0.01}\n' "$TODAY"
  printf '{"timestamp":"%sT10:00:00+0000","session_id":"b","project":"beta","model":"claude-opus-4-8","input_tokens":0,"output_tokens":1000,"cache_write_tokens":0,"cache_read_tokens":0,"estimated_cost_usd":0.02}\n' "$TODAY"
  printf '{"timestamp":"%sT09:00:00+0000","session_id":"c","project":"alpha","model":"claude-sonnet-4-6","input_tokens":0,"output_tokens":0,"cache_write_tokens":0,"cache_read_tokens":0,"estimated_cost_usd":0.05}\n' "$Y"
  printf '{"timestamp":"%sT09:00:00+0000","session_id":"d","project":"gamma","model":"claude-haiku-4-5","input_tokens":0,"output_tokens":0,"cache_write_tokens":0,"cache_read_tokens":0,"estimated_cost_usd":0.99}\n' "$OLD"
} > "$M/costs.jsonl"

OUT=$(CLAUDE_METRICS_DIR="$M" sh "$BIN")
printf '%s' "$OUT" | grep -q "Today:.*0.03"     && ok "today = 0.03"          || bad "today" "$OUT"
printf '%s' "$OUT" | grep -q "Last 7d:.*0.08"   && ok "last7d = 0.08"         || bad "last7d" "$OUT"
printf '%s' "$OUT" | grep -q "All-time:.*1.07"  && ok "all-time = 1.07"       || bad "alltime" "$OUT"
printf '%s' "$OUT" | grep -q "beta"             && ok "by-project lists beta" || bad "by-project" "$OUT"
if printf '%s' "$OUT" | grep -q "gamma"; then bad "gamma excluded from 7d" "$OUT"; else ok "gamma excluded from 7d window"; fi

# CSV mode
COUT=$(CLAUDE_METRICS_DIR="$M" sh "$BIN" csv)
printf '%s' "$COUT" | head -1 | grep -q "timestamp,project,model" && ok "csv header" || bad "csv header" "$COUT"
printf '%s' "$COUT" | grep -q "alpha" && ok "csv has data rows" || bad "csv data" "$COUT"

# Missing file -> friendly message, exit 0
rm -f "$M/costs.jsonl"
MOUT=$(CLAUDE_METRICS_DIR="$M" sh "$BIN"); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$MOUT" | grep -qi "no cost data" && ok "missing file -> friendly msg, exit 0" || bad "missing file" "rc=$rc $MOUT"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
