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

echo "PASS"
