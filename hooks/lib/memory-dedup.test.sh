#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0

# Hermetic default: most cases below exercise search() (the MEMORY_SEARCH_CMD
# seam) in isolation and expect membackend_dedup to miss (exit 3) so the stub
# alone drives the verdict. Without this, they'd silently pick up whatever
# real backend is configured on the machine running the suite (e.g.
# memoryBackend=local-embed after T15) and get REAL, test-irrelevant hits
# instead — cases that need a different backend already export/unset their
# own MEMORY_BACKEND around themselves.
export MEMORY_BACKEND=none

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

# 9. search command FAILS (rc!=0, e.g. leann missing) -> UNVERIFIED third token,
#    NOT a silent NEW (dead index must not look like novelty — 2026-08-16)
export MEMORY_SEARCH_CMD='false'
out=$(sh "$DIR/memory-dedup.sh" some-index "candidate text" 2>/dev/null)
check "search rc!=0 -> UNVERIFIED" "$out" "UNVERIFIED"

# 10. search runs but emits NOTHING (empty output, rc 0) -> UNVERIFIED
export MEMORY_SEARCH_CMD='true'
out=$(sh "$DIR/memory-dedup.sh" some-index "candidate text" 2>/dev/null)
check "empty search output -> UNVERIFIED" "$out" "UNVERIFIED"

# 11. healthy searches (cases 1-8) stay TWO-token: no UNVERIFIED on success path
export MEMORY_SEARCH_CMD='printf "[]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "candidate text")
printf '%s' "$out" | grep -q "UNVERIFIED" \
  && { echo "FAIL: healthy empty-results run must NOT be UNVERIFIED"; FAIL=$((FAIL+1)); } \
  || { echo "PASS: healthy run stays two-token"; PASS=$((PASS+1)); }

# 12. backend adapter says 3 (backend=none) -> falls through to the leann
#     path unchanged (same near-dup case as test 1, pinned explicitly so this
#     doesn't depend on the machine's real settings.json)
export MEMORY_BACKEND=none
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.4,\"text\":\"leann memory dedup candidate text lesson learned\",\"metadata\":{}}]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate text lesson learned")
check "adapter exit 3 (backend=none) -> leann path intact -> SKIP" "$out" "SKIP"
unset MEMORY_BACKEND

# 13. backend adapter succeeds (exit 0) -> its JSONL hits are used instead of
#     calling leann at all (MEMORY_SEARCH_CMD below would give NEW if it were
#     consulted — proves the adapter path wins, not just "did SKIP happen")
ADAPTER_STUB_DIR=$(mktemp -d)
cat > "$ADAPTER_STUB_DIR/membackend-local-embed.sh" <<'EOF'
#!/bin/sh
echo '{"score":0.9,"path":"x.md","snippet":"leann memory dedup candidate text lesson learned"}'
exit 0
EOF
chmod +x "$ADAPTER_STUB_DIR/membackend-local-embed.sh"
export MEMORY_BACKEND=local-embed
export MEMBACKEND_LIB_DIR="$ADAPTER_STUB_DIR"
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.0,\"text\":\"totally unrelated leann fallback text\",\"metadata\":{}}]"'
out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate text lesson learned")
check "adapter exit 0 -> its hits drive the verdict -> SKIP" "$out" "SKIP"
unset MEMORY_BACKEND
unset MEMBACKEND_LIB_DIR
rm -rf "$ADAPTER_STUB_DIR"

# 14. backend adapter reports SUCCESS (exit 0) but its stdout is unparseable
#     garbage -> must NOT masquerade as "zero matches" (a silent "0.0 NEW"
#     confident-wrong-verdict — reviewer repro). Must fall through to leann
#     exactly like ADAPTER_RC=3 does; leann here has a genuine near-dup, so
#     SKIP (not "0.0 NEW") proves the fallthrough actually ran, not just that
#     a message was printed.
GARBAGE_STUB_DIR=$(mktemp -d)
cat > "$GARBAGE_STUB_DIR/membackend-local-embed.sh" <<'EOF'
#!/bin/sh
echo 'not-json{garbage'
exit 0
EOF
chmod +x "$GARBAGE_STUB_DIR/membackend-local-embed.sh"
export MEMORY_BACKEND=local-embed
export MEMBACKEND_LIB_DIR="$GARBAGE_STUB_DIR"
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.4,\"text\":\"leann memory dedup candidate text lesson learned\",\"metadata\":{}}]"'

out=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate text lesson learned" 2>/dev/null)
check "adapter rc=0 + unparseable output -> falls through to leann -> SKIP (not silent 0.0 NEW)" "$out" "SKIP"

err=$(sh "$DIR/memory-dedup.sh" some-index "leann memory dedup candidate text lesson learned" 2>&1 1>/dev/null)
check "adapter rc=0 + unparseable output -> stderr notice surfaces" "$err" "unparseable"

unset MEMORY_BACKEND
unset MEMBACKEND_LIB_DIR
rm -rf "$GARBAGE_STUB_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
