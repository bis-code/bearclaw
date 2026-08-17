#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export MEMORY_STORE_DIR="$TMP/store"
. "$DIR/memory-store.sh"

memstore_init
[ -d "$MEMSTORE_RAW" ]     || { echo "FAIL: raw dir missing"; exit 1; }
[ -d "$MEMSTORE_SIGNALS" ] || { echo "FAIL: signals dir missing"; exit 1; }
[ -d "$MEMSTORE_DONE" ]    || { echo "FAIL: done dir missing"; exit 1; }
[ -d "$MEMSTORE_USAGE" ]   || { echo "FAIL: usage dir missing"; exit 1; }

# enqueue raw + list
P=$(memstore_enqueue_raw '{"session":"s1"}')
[ -f "$P" ] || { echo "FAIL: enqueue did not write a file"; exit 1; }
grep -q '"session":"s1"' "$P" || { echo "FAIL: raw content not written"; exit 1; }
n=$(memstore_list_raw | wc -l | tr -d ' ')
[ "$n" = "1" ] || { echo "FAIL: expected 1 pending raw, got $n"; exit 1; }

# mark done moves it out of raw, into done
memstore_mark_done "$P"
[ ! -f "$P" ] || { echo "FAIL: raw still present after mark-done"; exit 1; }
d=$(ls "$MEMSTORE_DONE" | wc -l | tr -d ' ')
[ "$d" = "1" ] || { echo "FAIL: expected 1 done file, got $d"; exit 1; }
n=$(memstore_list_raw | wc -l | tr -d ' ')
[ "$n" = "0" ] || { echo "FAIL: list_raw should be empty after mark-done, got $n"; exit 1; }

# append signal
memstore_append_signal sess-A '{"kind":"resolved"}'
memstore_append_signal sess-A '{"kind":"praise"}'
lc=$(wc -l < "$MEMSTORE_SIGNALS/sess-A.jsonl" | tr -d ' ')
[ "$lc" = "2" ] || { echo "FAIL: expected 2 signal lines, got $lc"; exit 1; }

# append usage
memstore_append_usage recall-log.jsonl '{"id":"x"}'
[ -f "$MEMSTORE_USAGE/recall-log.jsonl" ] || { echo "FAIL: usage log missing"; exit 1; }
grep -q '"id":"x"' "$MEMSTORE_USAGE/recall-log.jsonl" || { echo "FAIL: usage line not written"; exit 1; }

# memstore_init is idempotent
memstore_init
[ $? -eq 0 ] || { echo "FAIL: memstore_init returned non-zero"; exit 1; }
[ -d "$MEMSTORE_RAW" ]     || { echo "FAIL: raw dir missing after second init"; exit 1; }
[ -d "$MEMSTORE_SIGNALS" ] || { echo "FAIL: signals dir missing after second init"; exit 1; }
[ -d "$MEMSTORE_DONE" ]    || { echo "FAIL: done dir missing after second init"; exit 1; }
[ -d "$MEMSTORE_USAGE" ]   || { echo "FAIL: usage dir missing after second init"; exit 1; }

# --- retention: the audit trail must stay bounded -------------------------
# done/ grew to 490 pointers (6 weeks, ~11/day) with nothing pruning it, and
# orphaned signal files accumulated alongside. Retention is age-based so the
# recent audit trail survives.
memstore_init
touch "$MEMSTORE_DONE/old.json" "$MEMSTORE_DONE/new.json"
touch "$MEMSTORE_SIGNALS/old.jsonl" "$MEMSTORE_SIGNALS/new.jsonl"
touch -t 202601010000 "$MEMSTORE_DONE/old.json" "$MEMSTORE_SIGNALS/old.jsonl"
KEEP=$(memstore_enqueue_raw '{"session":"pending"}')
touch -t 202601010000 "$KEEP"

memstore_prune_done 30

[ ! -f "$MEMSTORE_DONE/old.json" ]      || { echo "FAIL: stale done pointer not pruned"; exit 1; }
[ -f "$MEMSTORE_DONE/new.json" ]        || { echo "FAIL: recent done pointer must be kept"; exit 1; }
[ ! -f "$MEMSTORE_SIGNALS/old.jsonl" ]  || { echo "FAIL: stale signal file not pruned"; exit 1; }
[ -f "$MEMSTORE_SIGNALS/new.jsonl" ]    || { echo "FAIL: recent signal file must be kept"; exit 1; }
# Pending work is never pruned, however old -- it is undrained, not audit.
[ -f "$KEEP" ] || { echo "FAIL: pending raw capture must NEVER be pruned by age"; exit 1; }

# A bad or missing retention value must not delete anything.
touch "$MEMSTORE_DONE/old2.json"; touch -t 202601010000 "$MEMSTORE_DONE/old2.json"
memstore_prune_done "abc"
[ -f "$MEMSTORE_DONE/old2.json" ] || { echo "FAIL: invalid DAYS must be a no-op, not a delete"; exit 1; }
memstore_prune_done 0
[ -f "$MEMSTORE_DONE/old2.json" ] || { echo "FAIL: DAYS=0 must be a no-op, not a delete"; exit 1; }

echo "PASS"
