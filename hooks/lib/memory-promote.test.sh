#!/bin/sh
# Tests for memory-promote.sh — promotion flow with a stubbed dedup search.
# NO set -e: several cases capture intentionally non-zero exits (3/4/1).
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "ok   $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL $1 ($2)"; FAIL=$((FAIL+1)); }

GDIR="$TMP/global"; mkdir -p "$GDIR"
printf '<!-- index -->\n' > "$GDIR/MEMORY.md"

ENTRY="$TMP/lesson-one.md"
cat > "$ENTRY" <<'EOF'
---
name: lesson-one
description: a distinctive test lesson about frobnicating the widget cache
---

Frobnicate the widget cache before restarting.
EOF

# t1: dry-run promotes nothing, prints plan
out=$(GLOBAL_MEM_DIR="$GDIR" MEMORY_SEARCH_CMD='printf "[]"' sh "$DIR/memory-promote.sh" "$ENTRY" --dry-run)
printf '%s' "$out" | grep -q "would: cp" && ok "t1 dry-run prints plan" || bad "t1" "$out"
[ ! -e "$GDIR/lesson-one.md" ] && ok "t1 dry-run writes nothing" || bad "t1w" "file written"

# t2: real promote copies entry + appends index line + prints commit command
out=$(GLOBAL_MEM_DIR="$GDIR" MEMORY_SEARCH_CMD='printf "[]"' sh "$DIR/memory-promote.sh" "$ENTRY")
[ -f "$GDIR/lesson-one.md" ] && ok "t2 entry copied" || bad "t2" "no file"
grep -q "lesson-one.md) — a distinctive test lesson" "$GDIR/MEMORY.md" && ok "t2 index line appended" || bad "t2i" "$(cat "$GDIR/MEMORY.md")"
printf '%s' "$out" | grep -q "git -C .* add memory-global/lesson-one.md" && ok "t2 commit command printed" || bad "t2c" "$out"

# t3: promoting the same slug again refuses (update-in-place doctrine)
out=$(GLOBAL_MEM_DIR="$GDIR" MEMORY_SEARCH_CMD='printf "[]"' sh "$DIR/memory-promote.sh" "$ENTRY" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "already exists" && ok "t3 duplicate slug refused" || bad "t3" "rc=$rc $out"

# t4: near-duplicate content -> SKIP exit 3
ENTRY2="$TMP/lesson-two.md"
printf -- '---\nname: lesson-two\ndescription: frobnicating widgets again\n---\nbody\n' > "$ENTRY2"
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"a\",\"score\":1.2,\"text\":\"lesson-two frobnicating widgets again body\",\"metadata\":{}}]"'
out=$(GLOBAL_MEM_DIR="$GDIR" sh "$DIR/memory-promote.sh" "$ENTRY2" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "t4 near-dup SKIP exit 3" || bad "t4" "rc=$rc $out"
unset MEMORY_SEARCH_CMD

# t5: UNVERIFIED search + grep hit -> exit 4; --force promotes
cp "$GDIR/lesson-one.md" "$GDIR/mentions-lesson-three.md"
printf 'see lesson-three for details\n' >> "$GDIR/mentions-lesson-three.md"
ENTRY3="$TMP/lesson-three.md"
printf -- '---\nname: lesson-three\ndescription: a third lesson\n---\nbody three\n' > "$ENTRY3"
out=$(GLOBAL_MEM_DIR="$GDIR" MEMORY_SEARCH_CMD='false' sh "$DIR/memory-promote.sh" "$ENTRY3" 2>&1); rc=$?
[ "$rc" -eq 4 ] && ok "t5 UNVERIFIED+grep-hit blocks (exit 4)" || bad "t5" "rc=$rc $out"
out=$(GLOBAL_MEM_DIR="$GDIR" MEMORY_SEARCH_CMD='false' sh "$DIR/memory-promote.sh" "$ENTRY3" --force 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -f "$GDIR/lesson-three.md" ] && ok "t5 --force promotes" || bad "t5f" "rc=$rc"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
