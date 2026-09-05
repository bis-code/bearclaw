#!/bin/sh
# Tests for sessionstart-memory-tuning-nudge.sh
#
# The behaviour under test is mostly SILENCE, which is the hard thing to test and
# the whole value of the hook: it must stay quiet until a decision is genuinely
# available. A hook that fires early trains you to ignore it.
set +e
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/sessionstart-memory-tuning-nudge.sh"
FAILS=0

ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS+1)); }
check(){ [ "$2" = "$3" ] && ok "$1" || { bad "$1"; printf '       want [%s] got [%s]\n' "$3" "$2"; }; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a log with N lines BEFORE the 519 baseline plus `organic` lines after it,
# each spending `errslots` of its 4 slots on ERRORS.
mklog() { # <file> <organic-count> <errors-slots-per-recall>
  _f="$1"; _n="$2"; _e="$3"
  : > "$_f"
  _i=0
  while [ "$_i" -lt 519 ]; do
    printf '{"ts":1,"ids":["ERRORS","ERRORS","ERRORS","ERRORS"]}\n' >> "$_f"
    _i=$((_i+1))
  done
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _ids=""; _j=0
    while [ "$_j" -lt 4 ]; do
      if [ "$_j" -lt "$_e" ]; then _ids="$_ids\"ERRORS\","; else _ids="$_ids\"curated-$_j\","; fi
      _j=$((_j+1))
    done
    printf '{"ts":2,"ids":[%s]}\n' "$(printf '%s' "$_ids" | sed 's/,$//')" >> "$_f"
    _i=$((_i+1))
  done
}

run() { # <log> <state> -> stdout
  RECALL_LOG_PATH="$1" XDG_STATE_HOME="$2" MEMTUNE_NUDGE_FORCE=1 sh "$HOOK" 2>/dev/null
}

# --- silent below the sample bar -------------------------------------------
# 40 recalls at a 100% ERRORS share: the share is damning, the sample is not.
# Firing here would be acting on noise.
mklog "$TMP/small.jsonl" 40 4
OUT=$(run "$TMP/small.jsonl" "$TMP/s1")
check "stays silent below the recall bar, however bad the share looks" "$OUT" ""

# --- silent when the share is fine ------------------------------------------
# Plenty of traffic, ERRORS taking 1 of 4 slots = 25%. Nothing to decide.
mklog "$TMP/lowshare.jsonl" 200 1
OUT=$(run "$TMP/lowshare.jsonl" "$TMP/s2")
check "stays silent when ERRORS is not crowding" "$OUT" ""

# --- the baseline is honoured ------------------------------------------------
# 519 pre-baseline lines are 100% ERRORS. Counting them would trip every gate;
# only the organic slice may count.
mklog "$TMP/onlyprobe.jsonl" 0 0
OUT=$(run "$TMP/onlyprobe.jsonl" "$TMP/s3")
check "ignores everything at or before the 519 baseline" "$OUT" ""

# --- fires when BOTH conditions hold ----------------------------------------
mklog "$TMP/hot.jsonl" 150 2   # 150 recalls, 2/4 slots = 50%
OUT=$(run "$TMP/hot.jsonl" "$TMP/s4")
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 \
  && ok "fires once the sample AND the share both clear their bars" \
  || bad "fires once the sample AND the share both clear their bars"

printf '%s' "$OUT" | grep -q '150 organic recalls' \
  && ok "reports the organic count, not the whole log" \
  || bad "reports the organic count, not the whole log"

printf '%s' "$OUT" | grep -q '50% of injected recall slots' \
  && ok "reports the slot share, not the share of recalls" \
  || bad "reports the slot share, not the share of recalls"

# --- once ever, not every session -------------------------------------------
S5="$TMP/s5"
RECALL_LOG_PATH="$TMP/hot.jsonl" XDG_STATE_HOME="$S5" sh "$HOOK" >/dev/null 2>&1
OUT=$(RECALL_LOG_PATH="$TMP/hot.jsonl" XDG_STATE_HOME="$S5" sh "$HOOK" 2>/dev/null)
check "does not repeat itself on the next session" "$OUT" ""

# --- silenceable --------------------------------------------------------------
S6="$TMP/s6"; mkdir -p "$S6/claude-setup"; : > "$S6/claude-setup/memory-tuning-nudge.off"
OUT=$(run "$TMP/hot.jsonl" "$S6")
check "honours the off switch" "$OUT" ""

# --- fails open ---------------------------------------------------------------
OUT=$(run "$TMP/does-not-exist.jsonl" "$TMP/s7")
check "silent when there is no recall log at all" "$OUT" ""

printf '%s' '' > "$TMP/empty.jsonl"
OUT=$(run "$TMP/empty.jsonl" "$TMP/s8")
check "silent on an empty log" "$OUT" ""

[ "$FAILS" -eq 0 ] || exit 1
exit 0
