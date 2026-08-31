#!/bin/sh
# memory-store.test.sh — usage-log primitives only (T9: the capture-queue
# tier and its tests were removed with the review-queue machinery).
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export MEMORY_STORE_DIR="$TMP/store"
. "$DIR/memory-store.sh"

memstore_init
[ -d "$MEMSTORE_USAGE" ] || { echo "FAIL: usage dir missing"; exit 1; }

# append usage
memstore_append_usage recall-log.jsonl '{"id":"x"}'
[ -f "$MEMSTORE_USAGE/recall-log.jsonl" ] || { echo "FAIL: usage log missing"; exit 1; }
grep -q '"id":"x"' "$MEMSTORE_USAGE/recall-log.jsonl" || { echo "FAIL: usage line not written"; exit 1; }

# multiple appends accumulate
memstore_append_usage recall-log.jsonl '{"id":"y"}'
lc=$(wc -l < "$MEMSTORE_USAGE/recall-log.jsonl" | tr -d ' ')
[ "$lc" = "2" ] || { echo "FAIL: expected 2 usage lines, got $lc"; exit 1; }

# memstore_init is idempotent
memstore_init
[ $? -eq 0 ] || { echo "FAIL: memstore_init returned non-zero"; exit 1; }
[ -d "$MEMSTORE_USAGE" ] || { echo "FAIL: usage dir missing after second init"; exit 1; }

echo "PASS"
