#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0

check() {
  label="$1"; out="$2"; expect="$3"
  if printf '%s' "$out" | grep -q "$expect"; then
    echo "PASS: $label"
    PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected $expect, got: $out"
    FAIL=$((FAIL+1))
  fi
}

# 1. near-dup -> SKIP: hit text is nearly identical to candidate (high word overlap)
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.4,\"text\":\"leann memory dedup candidate text lesson learned\",\"metadata\":{}}]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate text lesson learned")
check "near-dup -> SKIP" "$out" "SKIP"

# 2. new lesson sharing domain vocab -> NEW  (the former false-SKIP regression)
#    candidate is about a NEW lesson; hit shares words "leann" and "memory" but is different content
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.35,\"text\":\"leann memory index rebuild takes several minutes run in background\",\"metadata\":{}}]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory search returns empty when index is corrupted rebuild to fix")
check "domain-vocab overlap only -> NEW (false-SKIP regression)" "$out" "NEW"

# 3. empty results -> 0.0 NEW (fail-open)
export MEMORY_SEARCH_CMD='printf "[]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "candidate text")
check "empty results -> NEW" "$out" "NEW"

# 4. malformed JSON -> NEW (fail-open, no crash)
export MEMORY_SEARCH_CMD='printf "not-json{"'
out=$(sh "$DIR/memory-dedup.sh" some-index "candidate text")
check "malformed JSON -> NEW" "$out" "NEW"

# 5. missing .text on hits -> NEW (fail-open, no crash)
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.8}]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "candidate text")
check "missing .text on hits -> NEW" "$out" "NEW"

# 6. max-over-hits: LATER hit (not first/highest-score) has the highest text overlap -> SKIP
#    first hit: different content, low overlap; second hit: nearly identical
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.6,\"text\":\"unrelated topic about git hooks dispatch\",\"metadata\":{}},{\"id\":\"b\",\"score\":0.9,\"text\":\"leann memory dedup candidate text lesson learned\",\"metadata\":{}}]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate text lesson learned")
check "max over non-first hit -> SKIP" "$out" "SKIP"

# 7. threshold override: moderate overlap (~0.8 Jaccard) straddles threshold
# exact-same text always gives Jaccard 1.0 so it SKIPs regardless of threshold;
# the interesting case is a moderate-overlap pair tested at two threshold values:
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":0.9,\"text\":\"memory dedup index search\",\"metadata\":{}}]"'
out=$(MEMORY_DEDUP_THRESHOLD=0.9 sh "$DIR/memory-dedup.sh" some-index "memory dedup index search threshold")
check "threshold override 0.9 with ~0.8 overlap -> NEW" "$out" "NEW"

export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":0.9,\"text\":\"memory dedup index search\",\"metadata\":{}}]"'
out=$(MEMORY_DEDUP_THRESHOLD=0.5 sh "$DIR/memory-dedup.sh" some-index "memory dedup index search threshold")
check "threshold override 0.5 with ~0.8 overlap -> SKIP" "$out" "SKIP"

# 8. injection-safety: hit .text containing ''' and backslashes must NOT corrupt
#    the python program (JSON arrives via stdin, not interpolated into source).
#    The old heredoc-interpolation would syntax-error on the ''' -> false NEW.
NASTY=$(mktemp)
cat > "$NASTY" <<'NJEOF'
[{"id":"a","score":1.2,"text":"leann memory dedup candidate triple quote ''' and backslash \\ done","metadata":{}}]
NJEOF
export MEMORY_SEARCH_CMD="cat $NASTY"
out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate triple quote and backslash done")
check "injection-safe: ''' + backslash in hit text -> SKIP (not corrupted to NEW)" "$out" "SKIP"
rm -f "$NASTY"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
