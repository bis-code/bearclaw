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

# Case 5: LOCK HELD by another build -> second run exits cleanly WITHOUT building
TMP3=$(mktemp -d); SRC3="$TMP3/src"; mkdir -p "$SRC3"; printf 'w' > "$SRC3/c.md"
export XDG_STATE_HOME="$TMP3/state"
export MEMORY_BUILD_CMD="echo BUILT"
mkdir -p "$TMP3/state/claude-memory/lockidx.lock"
out=$(sh "$DIR/memory-index-freshness.sh" lockidx "$SRC3"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: locked run should exit 0 (got $rc)"; exit 1; }
echo "$out" | grep -q BUILT && { echo "FAIL: locked run must NOT build"; exit 1; }
# lock released by the OTHER holder -> next run builds
rmdir "$TMP3/state/claude-memory/lockidx.lock"
out=$(sh "$DIR/memory-index-freshness.sh" lockidx "$SRC3")
echo "$out" | grep -q BUILT || { echo "FAIL: post-lock run should build"; exit 1; }
# lock is released after OUR build too (trap) -> immediate re-run possible
[ -d "$TMP3/state/claude-memory/lockidx.lock" ] && { echo "FAIL: lock leaked after build"; exit 1; }

# Case 6: SRC is a SYMLINK — the production shape. install.sh points the config
# root's memory-global at this repo rather than copying it, but every case above
# passes a REAL directory, so the suite went green while the staleness check was
# a permanent no-op on every real machine. find does not follow a symlinked
# starting point without -L, and `[ -d "$SRC" ]` does not catch it because -d
# DOES follow. Regression guard.
TMP4=$(mktemp -d); REAL4="$TMP4/real"; mkdir -p "$REAL4"; printf 'q' > "$REAL4/d.md"
ln -s "$REAL4" "$TMP4/link"
export XDG_STATE_HOME="$TMP4/state"
export MEMORY_BUILD_CMD="echo BUILT"
out=$(sh "$DIR/memory-index-freshness.sh" symidx "$TMP4/link")
echo "$out" | grep -q BUILT || { echo "FAIL: first run through a symlink should build"; exit 1; }
out=$(sh "$DIR/memory-index-freshness.sh" symidx "$TMP4/link")
echo "$out" | grep -q BUILT && { echo "FAIL: unchanged symlinked src should skip"; exit 1; }
sleep 1; printf 'r' >> "$REAL4/d.md"
out=$(sh "$DIR/memory-index-freshness.sh" symidx "$TMP4/link")
echo "$out" | grep -q BUILT || { echo "FAIL: edit behind a SYMLINK must rebuild (find needs -L)"; exit 1; }

echo "PASS"
