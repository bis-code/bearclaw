set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); SRC="$TMP/src"; mkdir -p "$SRC"; printf 'x' > "$SRC/a.md"
export XDG_STATE_HOME="$TMP/state"
export MEMORY_BUILD_CMD="echo BUILT"   # seam: stub the actual leann build
out=$(sh "$DIR/memory-index-freshness.sh" testidx "$SRC")
echo "$out" | grep -q BUILT || { echo "FAIL: first run should build"; exit 1; }
out=$(sh "$DIR/memory-index-freshness.sh" testidx "$SRC")
echo "$out" | grep -q BUILT && { echo "FAIL: unchanged should skip"; exit 1; }
sleep 1; printf 'y' >> "$SRC/a.md"
out=$(sh "$DIR/memory-index-freshness.sh" testidx "$SRC")
echo "$out" | grep -q BUILT || { echo "FAIL: changed should rebuild"; exit 1; }

# Case 4: MEMORY_BUILD_CMD UNSET — exercises the real default path (the production path).
# Stubs the builder by creating a fake memory-index-build.sh next to freshness.sh.
TMP2=$(mktemp -d); SRC2="$TMP2/src"; mkdir -p "$SRC2"; printf 'z' > "$SRC2/b.md"
export XDG_STATE_HOME="$TMP2/state"
cp "$DIR/memory-index-freshness.sh" "$TMP2/memory-index-freshness.sh"
mkdir -p "$TMP2/lib"
printf '#!/bin/sh\necho SENTINEL_DEFAULT_PATH\n' > "$TMP2/lib/memory-index-build.sh"
chmod +x "$TMP2/lib/memory-index-build.sh"
unset MEMORY_BUILD_CMD
out=$(sh "$TMP2/memory-index-freshness.sh" testidx-default "$SRC2")
echo "$out" | grep -q SENTINEL_DEFAULT_PATH || { echo "FAIL: unset MEMORY_BUILD_CMD should invoke default builder"; exit 1; }

echo "PASS"
