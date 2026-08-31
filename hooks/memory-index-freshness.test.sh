set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); SRC="$TMP/src"; mkdir -p "$SRC"; printf 'x' > "$SRC/a.md"
export XDG_STATE_HOME="$TMP/state"
export MEMORY_BUILD_CMD="echo BUILT"   # seam: stub the real backend build
out=$(sh "$DIR/memory-index-freshness.sh" testidx "$SRC")
echo "$out" | grep -q BUILT || { echo "FAIL: first run should build"; exit 1; }
out=$(sh "$DIR/memory-index-freshness.sh" testidx "$SRC")
echo "$out" | grep -q BUILT && { echo "FAIL: unchanged should skip"; exit 1; }
sleep 1; printf 'y' >> "$SRC/a.md"
out=$(sh "$DIR/memory-index-freshness.sh" testidx "$SRC")
echo "$out" | grep -q BUILT || { echo "FAIL: changed should rebuild"; exit 1; }

# Case 4: MEMORY_BUILD_CMD UNSET — exercises the real default path (the
# production path), which is now the configured BACKEND's own build via the
# memory-backend.sh dispatcher. It used to be leann's lib/memory-index-build.sh,
# retired with the engine, which left the default branch a silent no-op: this
# case kept passing against a stub of a file production no longer had.
# The whole hooks/lib is copied so the dispatcher resolves its own sibling,
# then ONLY the local-embed adapter is replaced by a sentinel — that proves the
# path runs end to end (freshness -> dispatcher -> adapter) rather than stubbing
# the seam under test.
TMP2=$(mktemp -d); SRC2="$TMP2/src"; mkdir -p "$SRC2"; printf 'z' > "$SRC2/b.md"
export XDG_STATE_HOME="$TMP2/state"
cp "$DIR/memory-index-freshness.sh" "$TMP2/memory-index-freshness.sh"
mkdir -p "$TMP2/lib"
cp "$DIR/lib/memory-backend.sh" "$TMP2/lib/memory-backend.sh"
printf '#!/bin/sh\necho SENTINEL_DEFAULT_PATH "$@"\n' > "$TMP2/lib/membackend-local-embed.sh"
chmod +x "$TMP2/lib/membackend-local-embed.sh"
unset MEMORY_BUILD_CMD
out=$(MEMORY_BACKEND=local-embed sh "$TMP2/memory-index-freshness.sh" testidx-default "$SRC2")
echo "$out" | grep -q SENTINEL_DEFAULT_PATH || { echo "FAIL: unset MEMORY_BUILD_CMD should dispatch to the backend build"; exit 1; }
# ...and it must pass the corpus NAME and DIR, in that order — the adapter
# derives the index key from the name, so a swapped pair indexes into the
# wrong file while still exiting 0.
echo "$out" | grep -q "SENTINEL_DEFAULT_PATH build testidx-default $SRC2" \
  || { echo "FAIL: backend build got wrong args: $out"; exit 1; }

# Case 4b: backend "none" (the public twin's default) must no-op, and must NOT
# stamp — stamping would mean "indexed" for a corpus nothing ever indexed.
TMP2B=$(mktemp -d); SRC2B="$TMP2B/src"; mkdir -p "$SRC2B"; printf 'z' > "$SRC2B/b.md"
out=$(XDG_STATE_HOME="$TMP2B/state" MEMORY_BACKEND=none sh "$TMP2/memory-index-freshness.sh" noneidx "$SRC2B"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: backend none should exit 0 (got $rc)"; exit 1; }
ls "$TMP2B/state/claude-memory/"noneidx*.built >/dev/null 2>&1 \
  && { echo "FAIL: backend none must not write a built stamp"; exit 1; }

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

# Case 7: an EMPTY corpus dir builds once, then stops. The build itself must
# report success for that to hold: while it returned non-zero the stamp was
# never written, so every SessionStart rediscovered the same empty directory and
# rebuilt it, forever.
TMP5=$(mktemp -d); SRC5="$TMP5/src"; mkdir -p "$SRC5"
export XDG_STATE_HOME="$TMP5/state"
export MEMORY_BUILD_CMD="echo BUILT"
out=$(sh "$DIR/memory-index-freshness.sh" emptyidx "$SRC5")
echo "$out" | grep -q BUILT || { echo "FAIL: empty corpus should build once"; exit 1; }
out=$(sh "$DIR/memory-index-freshness.sh" emptyidx "$SRC5")
echo "$out" | grep -q BUILT && { echo "FAIL: empty corpus must not rebuild every run"; exit 1; }

# Case 8: the machine-wide lock caps concurrent builds across DIFFERENT corpora.
# Per-corpus locks cannot do this: with one index file per tier they no longer
# conflict, so ten repo tiers waking together would all build at once — 52s of
# five-core CPU each, measured. A capped-out run must exit 0, must not build, and
# must not leave the stamp behind, so the next session retries it.
TMP6=$(mktemp -d); SRC6="$TMP6/src"; mkdir -p "$SRC6"; printf 'k' > "$SRC6/e.md"
export XDG_STATE_HOME="$TMP6/state"
mkdir -p "$TMP6/state/claude-memory/build.lock"
out=$(sh "$DIR/memory-index-freshness.sh" capidx "$SRC6"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: capped run should exit 0 (got $rc)"; exit 1; }
echo "$out" | grep -q BUILT && { echo "FAIL: capped run must NOT build"; exit 1; }
ls "$TMP6/state/claude-memory/"capidx*.built >/dev/null 2>&1 \
  && { echo "FAIL: capped run must not stamp"; exit 1; }
# our per-corpus lock must be released even though we bailed on the global one,
# or one capped run would block that corpus until the 30-minute stale break.
[ -d "$TMP6/state/claude-memory/capidx.lock" ] && { echo "FAIL: per-corpus lock leaked on cap"; exit 1; }
# global lock freed by its holder -> next run builds, and releases both locks
rmdir "$TMP6/state/claude-memory/build.lock"
out=$(sh "$DIR/memory-index-freshness.sh" capidx "$SRC6")
echo "$out" | grep -q BUILT || { echo "FAIL: post-cap run should build"; exit 1; }
[ -d "$TMP6/state/claude-memory/build.lock" ] && { echo "FAIL: global lock leaked after build"; exit 1; }

# Case 9: the stamp is namespaced per backend, and a legacy un-namespaced stamp
# does not suppress the first build. 10 such stamps are on this machine from
# before leann was retired, with no index behind any of them; inheriting that
# claim means a new backend never indexes at all.
TMP7=$(mktemp -d); SRC7="$TMP7/src"; mkdir -p "$SRC7"; printf 'm' > "$SRC7/f.md"
export XDG_STATE_HOME="$TMP7/state"
mkdir -p "$TMP7/state/claude-memory"
touch "$TMP7/state/claude-memory/legacyidx.built"   # the pre-namespacing stamp
sleep 1
out=$(MEMORY_BACKEND=local-embed sh "$DIR/memory-index-freshness.sh" legacyidx "$SRC7")
echo "$out" | grep -q BUILT || { echo "FAIL: a legacy stamp must not suppress the first build"; exit 1; }
[ -f "$TMP7/state/claude-memory/legacyidx.local-embed.built" ] \
  || { echo "FAIL: stamp should be namespaced by backend"; exit 1; }
[ -f "$TMP7/state/claude-memory/legacyidx.built" ] \
  && { echo "FAIL: legacy stamp should be retired, not left to confuse"; exit 1; }

echo "PASS"
