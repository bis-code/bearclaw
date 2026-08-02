#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)

# Test 1: Normal case with populated log
echo "Test 1: flagging with populated log..."
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
MEM="$TMP/mem"; mkdir -p "$MEM"
printf 'a\n' > "$MEM/hot.md"
printf 'b\n' > "$MEM/cold.md"
printf 'index\n' > "$MEM/MEMORY.md"   # must be excluded

. "$DIR/memory-store.sh"; memstore_init
NOW=$(date +%s)
memstore_append_usage recall-log.jsonl "{\"ts\":$NOW,\"ids\":[\"hot\"]}"

out=$(sh "$DIR/memory-prune.sh" "$MEM" 30)
echo "$out" | grep -q "cold" || { echo "FAIL T1: cold (never-recalled) should be flagged"; exit 1; }
echo "$out" | grep -q "hot"  && { echo "FAIL T1: hot (recently recalled) should NOT be flagged"; exit 1; }
echo "$out" | grep -q "MEMORY" && { echo "FAIL T1: MEMORY.md must be excluded"; exit 1; }
[ -f "$MEM/cold.md" ] || { echo "FAIL T1: prune must never delete"; exit 1; }
echo "PASS: T1"
rm -rf "$TMP"

# Test 2: Absent log -> nothing flagged, notice on stderr
echo "Test 2: absent log triggers early exit..."
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
MEM="$TMP/mem"; mkdir -p "$MEM"
printf 'a\n' > "$MEM/entry1.md"
printf 'b\n' > "$MEM/entry2.md"
. "$DIR/memory-store.sh"; memstore_init
# DON'T populate the log

out=$(sh "$DIR/memory-prune.sh" "$MEM" 30 2>/dev/null)
[ -z "$out" ] || { echo "FAIL T2: should output nothing when log absent"; exit 1; }
echo "PASS: T2"
rm -rf "$TMP"

# Test 3: Empty log -> nothing flagged, notice on stderr
echo "Test 3: empty log triggers early exit..."
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
MEM="$TMP/mem"; mkdir -p "$MEM"
printf 'a\n' > "$MEM/entry1.md"
printf 'b\n' > "$MEM/entry2.md"
. "$DIR/memory-store.sh"; memstore_init
# Create empty log
touch "$MEMSTORE_USAGE/recall-log.jsonl"

out=$(sh "$DIR/memory-prune.sh" "$MEM" 30 2>/dev/null)
[ -z "$out" ] || { echo "FAIL T3: should output nothing when log empty"; exit 1; }
echo "PASS: T3"
rm -rf "$TMP"

# Test 4: ERRORS*.md glob excludes all variants
echo "Test 4: ERRORS* glob exclusion..."
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
MEM="$TMP/mem"; mkdir -p "$MEM"
printf 'a\n' > "$MEM/entry1.md"
printf 'b\n' > "$MEM/ERRORS.md"
printf 'c\n' > "$MEM/ERRORS.archive.md"
printf 'd\n' > "$MEM/ERRORS-custom.md"
printf 'e\n' > "$MEM/MEMORY.md"
printf 'f\n' > "$MEM/README.md"

. "$DIR/memory-store.sh"; memstore_init
NOW=$(date +%s)
# Don't recall any entries, so entry1 will be flagged NEVER
memstore_append_usage recall-log.jsonl "{\"ts\":$NOW,\"ids\":[]}"

out=$(sh "$DIR/memory-prune.sh" "$MEM" 30)
echo "$out" | grep -q "entry1" || { echo "FAIL T4: entry1 should be flagged"; exit 1; }
echo "$out" | grep -q "ERRORS" && { echo "FAIL T4: no ERRORS* files should be in output"; exit 1; }
echo "$out" | grep -q "MEMORY" && { echo "FAIL T4: MEMORY.md must be excluded"; exit 1; }
echo "$out" | grep -q "README" && { echo "FAIL T4: README.md must be excluded"; exit 1; }
echo "PASS: T4"
rm -rf "$TMP"

# Test 5: slug-join — usage log keyed by stem matches the .md file with that stem.
# This proves the real recall→prune pipeline join: recall.py logs "deploy-notes"
# (from file_name="deploy-notes.md"), and prune.sh looks up the stem "deploy-notes".
echo "Test 5: slug-join pipeline (usage keyed by stem = prune join aligns)..."
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
MEM="$TMP/mem"; mkdir -p "$MEM"
printf 'content\n' > "$MEM/deploy-notes.md"
printf 'other\n'   > "$MEM/cold-entry.md"

. "$DIR/memory-store.sh"; memstore_init
NOW=$(date +%s)
memstore_append_usage recall-log.jsonl "{\"ts\":$NOW,\"ids\":[\"deploy-notes\"]}"

out=$(sh "$DIR/memory-prune.sh" "$MEM" 30)
echo "$out" | grep -q "cold-entry"    || { echo "FAIL T5: cold-entry should be flagged"; exit 1; }
echo "$out" | grep -q "deploy-notes" && { echo "FAIL T5: deploy-notes was recalled (by slug) — must NOT be flagged"; exit 1; }
echo "PASS: T5"
rm -rf "$TMP"

# Test 6: non-integer DAYS argument -> clean exit 0, no bogus output
echo "Test 6: non-integer DAYS exits cleanly..."
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
MEM="$TMP/mem"; mkdir -p "$MEM"
printf 'a\n' > "$MEM/entry1.md"
. "$DIR/memory-store.sh"; memstore_init
NOW=$(date +%s)
memstore_append_usage recall-log.jsonl "{\"ts\":$NOW,\"ids\":[]}"

out=$(sh "$DIR/memory-prune.sh" "$MEM" "abc" 2>/dev/null)
[ -z "$out" ] || { echo "FAIL T6: non-integer DAYS should produce no stdout output, got: $out"; exit 1; }
# Verify exit code is 0 (set -e at top of test file; we run in subshell to capture)
sh "$DIR/memory-prune.sh" "$MEM" "abc" 2>/dev/null || { echo "FAIL T6: non-integer DAYS should exit 0"; exit 1; }
echo "PASS: T6"
rm -rf "$TMP"

echo "ALL TESTS PASS"
