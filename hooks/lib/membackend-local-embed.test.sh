#!/bin/sh
# Tests for membackend-local-embed.sh + hooks/lib/local-embed.py (T15).
# Builds a tiny real index (small corpus, real fastembed) in an isolated
# XDG_STATE_HOME/MEMORY_VENV-independent sandbox and exercises the CLI
# surface the memory-backend.sh dispatcher relies on. Skips (not fails) when
# the memory venv / fastembed aren't installed on this machine — same
# fail-open contract the backend itself has toward callers.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; SKIP=0

check() {
  label="$1"; out="$2"; expect="$3"
  if printf '%s' "$out" | grep -q "$expect"; then
    echo "PASS: $label"; PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected /$expect/, got: $out"; FAIL=$((FAIL+1))
  fi
}

checkrc() {
  label="$1"; rc="$2"; expect="$3"
  if [ "$rc" -eq "$expect" ]; then
    echo "PASS: $label"; PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected rc=$expect, got rc=$rc"; FAIL=$((FAIL+1))
  fi
}

MEMORY_VENV="${MEMORY_VENV:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-venv}"
PY="$MEMORY_VENV/bin/python3"

if [ ! -x "$PY" ] || ! "$PY" -c 'import fastembed' >/dev/null 2>&1; then
  echo "SKIP: memory venv / fastembed not installed at $MEMORY_VENV — install.sh creates it"
  echo ""
  echo "Results: 0 passed, 0 failed (1 suite skipped)"
  exit 0
fi

TMP=$(mktemp -d)
export XDG_STATE_HOME="$TMP/state"
export MEMORY_VENV

# ---- missing index -> search exits 3 ----
out=$("$DIR/membackend-local-embed.sh" search main "anything" 5 2>&1); rc=$?
checkrc "search with no index -> exit 3" "$rc" 3
check "search with no index -> stderr reason" "$out" "no index"

# health also exits 3 with no index present — asked about the SAME tier the
# searches above use, because health is per tier now.
out=$("$DIR/membackend-local-embed.sh" health main 2>&1); rc=$?
checkrc "health with no index -> exit 3" "$rc" 3

# ---- build a tiny real corpus ----
CORPUS="$TMP/corpus"; mkdir -p "$CORPUS"
cat > "$CORPUS/apples.md" <<'EOF'
---
name: apples
---
Apples are a sweet crunchy fruit that grows on trees in temperate climates.
EOF
cat > "$CORPUS/databases.md" <<'EOF'
---
name: databases
---
A relational database stores structured rows in tables and answers queries with SQL.
EOF
cat > "$CORPUS/README.md" <<'EOF'
This file must be excluded from the corpus (README.md is always skipped).
EOF
# The pointer index. Its lines are dense with exactly the words a query uses, so
# they rank well and win slots — but a pointer cannot answer anything, and the
# entry it points at is the thing worth injecting. Measured on the real corpus:
# 11 of 118 injected slots went to MEMORY.md, none of which could ever be a hit.
cat > "$CORPUS/MEMORY.md" <<'EOF'
- [databases](databases.md) — a relational database stores structured rows in tables
- [apples](apples.md) — apples are a sweet crunchy fruit
EOF

# Built through the ADAPTER, not the python directly, and under the same corpus
# name the searches below pass. That agreement is the whole point of keying: a
# build and a search that disagree on the name now address different files, so
# a test that built one way and searched another would pass on an empty index.
BUILD_OUT=$("$DIR/membackend-local-embed.sh" build main "$CORPUS" 2>&1); rc=$?
checkrc "build exits 0" "$rc" 0
check "build reports a chunk count" "$BUILD_OUT" "built [0-9][0-9]* chunks"

# ---- health now reports OK (exit 0) ----
"$DIR/membackend-local-embed.sh" health main >/dev/null 2>&1; rc=$?
checkrc "health with index present -> exit 0" "$rc" 0

# ...and a tier that was never built is still unhealthy. Without this the gate
# in sessionstart-load-memory.sh would read HEALTHY for a repo with no index and
# go slim, yielding silence instead of falling back to an eager load.
"$DIR/membackend-local-embed.sh" health never-built >/dev/null 2>&1; rc=$?
checkrc "health for an unbuilt tier -> exit 3" "$rc" 3

# ---- search returns JSONL in the T7 adapter contract shape ----
SEARCH_OUT=$("$DIR/membackend-local-embed.sh" search main "structured rows in tables" 2 2>/dev/null); rc=$?
checkrc "search exits 0" "$rc" 0
LINES=$(printf '%s\n' "$SEARCH_OUT" | grep -c .)
check "search returns at least one line" "$LINES" "^[1-9]"
FIRST_LINE=$(printf '%s\n' "$SEARCH_OUT" | head -1)
echo "$FIRST_LINE" | python3 -c '
import json, sys
obj = json.load(sys.stdin)
assert isinstance(obj.get("score"), float), "score not a float"
assert isinstance(obj.get("path"), str) and obj["path"], "path missing"
assert isinstance(obj.get("snippet"), str) and obj["snippet"], "snippet missing"
' >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "PASS: first result line matches {score,path,snippet} contract"; PASS=$((PASS+1))
else
  echo "FAIL: first result line does not match contract: $FIRST_LINE"; FAIL=$((FAIL+1))
fi
# the databases.md chunk (closest to the query) should be the top hit
check "relevant chunk (databases.md) ranks first" "$FIRST_LINE" "databases.md"

# ...and no slot goes to the pointer index, whose line matches this query at
# least as well as the entry it points at.
ALL_OUT=$("$DIR/membackend-local-embed.sh" search main "structured rows in tables" 5 2>/dev/null)
if printf '%s' "$ALL_OUT" | grep -q 'MEMORY.md'; then
  echo "FAIL: the pointer index won an injection slot: $ALL_OUT"; FAIL=$((FAIL+1))
else
  echo "PASS: MEMORY.md is excluded from the corpus"; PASS=$((PASS+1))
fi

# ---- dedup: embeds the candidate file, returns nearest via the same search path
CAND="$TMP/cand.txt"
printf 'a relational store keeps rows in tables and answers queries' > "$CAND"
DEDUP_OUT=$("$DIR/membackend-local-embed.sh" dedup main "$CAND" 2>/dev/null); rc=$?
checkrc "dedup exits 0" "$rc" 0
check "dedup nearest hit is databases.md" "$DEDUP_OUT" "databases.md"

# dedup on a missing candidate file -> exit 1 (real error, not fallback)
"$DIR/membackend-local-embed.sh" dedup main "$TMP/does-not-exist.txt" >/dev/null 2>&1; rc=$?
checkrc "dedup missing candidate file -> exit 1" "$rc" 1

# ---- two corpora do not clobber each other ------------------------------
# The bug this guards: index_path() was a single hard-coded filename, so every
# tier wrote the same file. Building the repo tier silently replaced the global
# tier's vectors, and the global search then answered from the repo's corpus
# while health reported fine — wrong memory, delivered confidently.
CORPUS_B="$TMP/corpus-b"; mkdir -p "$CORPUS_B"
cat > "$CORPUS_B/volcanoes.md" <<'EOF'
---
name: volcanoes
---
A stratovolcano erupts viscous andesite lava and builds a steep conical profile.
EOF

"$DIR/membackend-local-embed.sh" build other "$CORPUS_B" >/dev/null 2>&1; rc=$?
checkrc "build of a second corpus exits 0" "$rc" 0

# A's index must still exist, still be healthy, and still answer from A.
"$DIR/membackend-local-embed.sh" health main >/dev/null 2>&1; rc=$?
checkrc "health A still exit 0 after B builds" "$rc" 0

A_AFTER=$("$DIR/membackend-local-embed.sh" search main "structured rows in tables" 4 2>/dev/null)
check "search A still returns A's paths after B builds" "$A_AFTER" "databases.md"
if printf '%s' "$A_AFTER" | grep -q 'volcanoes.md'; then
  echo "FAIL: search A leaked a path from corpus B: $A_AFTER"; FAIL=$((FAIL+1))
else
  echo "PASS: search A returns no path from corpus B"; PASS=$((PASS+1))
fi

# ...and symmetrically, B answers from B only.
B_OUT=$("$DIR/membackend-local-embed.sh" search other "viscous andesite lava" 4 2>/dev/null)
check "search B returns B's path" "$B_OUT" "volcanoes.md"
if printf '%s' "$B_OUT" | grep -q -e 'databases.md' -e 'apples.md'; then
  echo "FAIL: search B leaked a path from corpus A: $B_OUT"; FAIL=$((FAIL+1))
else
  echo "PASS: search B returns no path from corpus A"; PASS=$((PASS+1))
fi

# Two distinct index files on disk is the mechanism; assert it directly so a
# future refactor that reunifies them fails here rather than in a recall.
IDXN=$(ls "$XDG_STATE_HOME/claude-memory"/local-embed-*.json 2>/dev/null | grep -c .)
check "two separate index files exist" "$IDXN" "^2$"

# ---- search refuses an index built from a different corpus ---------------
# Repointing a tier at a moved or renamed memory directory must not return
# confident hits from whatever the stale index still holds.
out=$("$PY" "$DIR/local-embed.py" search "structured rows in tables" --top-k 2 \
        --index-key main --corpus "$TMP/some-other-dir" 2>&1); rc=$?
checkrc "search with a mismatched --corpus -> exit 3" "$rc" 3
check "mismatched --corpus explains itself" "$out" "rebuild"

# ---- a **Superseded:** section is not indexed ----------------------------
# `status: superseded` frontmatter retires a whole FILE, which cannot reach
# inside a grab-bag. ERRORS.md is one file with one slug holding ~54 dated
# entries, and four consumers depend on it staying one file, so retiring a single
# stale entry there needed a section-level marker. The entry stays readable, with
# its reasoning and correction intact; it just stops reaching prompts.
SUPC="$TMP/corpus-sup"; mkdir -p "$SUPC"
# BOTH marker forms. The dated one is what actually gets written, and testing
# only the bare form is how the first version of this shipped retiring nothing.
cat > "$SUPC/log.md" <<'EOF'
## [2026-01-01] The retired claim about dot products above one
**Superseded:** the engine this described is gone; scores are cosine now.
Dot-product scores routinely exceed 1.0 so a 0.85 threshold false-positives.

## [2026-01-03] Another retired claim, this one dated
**Superseded 2026-08-31:** the watcher this described no longer exists.
The index keeps shrinking to only the files that changed since the last build.

## [2026-01-02] The live claim about cosine similarity
Scores are cosine in zero to one, so a floor of 0.5 is meaningful.
EOF

"$DIR/membackend-local-embed.sh" build supidx "$SUPC" >/dev/null 2>&1
SUP_OUT=$("$DIR/membackend-local-embed.sh" search supidx "dot product scores above one threshold" 5 2>/dev/null)
if printf '%s' "$SUP_OUT" | grep -q 'retired claim\|false-positives'; then
  echo "FAIL: a **Superseded:** section was indexed: $SUP_OUT"; FAIL=$((FAIL+1))
else
  echo "PASS: **Superseded:** section is absent from the index"; PASS=$((PASS+1))
fi
SUP_DATED=$("$DIR/membackend-local-embed.sh" search supidx "index keeps shrinking to only changed files watcher" 5 2>/dev/null)
if printf '%s' "$SUP_DATED" | grep -q 'shrinking\|watcher'; then
  echo "FAIL: a DATED **Superseded ...:** section was indexed: $SUP_DATED"; FAIL=$((FAIL+1))
else
  echo "PASS: dated **Superseded <date>:** section is absent too"; PASS=$((PASS+1))
fi
# ...and its sibling in the same file is untouched.
SUP_OUT2=$("$DIR/membackend-local-embed.sh" search supidx "cosine similarity floor" 5 2>/dev/null)
check "the live section of the same file still indexes" "$SUP_OUT2" "log.md"

# ---- a file retired by frontmatter leaves the corpus ---------------------
# memory-recall.py also drops these at rank time, which covers a corpus not yet
# rebuilt. Skipping at index time is what stops a retired entry occupying a
# candidate slot: measured on the real corpus, a stale entry scored 0.7875 and
# led every live one.
cat > "$SUPC/retired.md" <<'EOF'
---
name: retired
status: superseded
---
Pistachio shells split along the suture as the kernel expands during roasting.
EOF
"$DIR/membackend-local-embed.sh" build supidx2 "$SUPC" >/dev/null 2>&1
RET_OUT=$("$DIR/membackend-local-embed.sh" search supidx2 "pistachio shells split during roasting" 5 2>/dev/null)
if printf '%s' "$RET_OUT" | grep -q 'retired.md'; then
  echo "FAIL: a frontmatter-retired file was indexed: $RET_OUT"; FAIL=$((FAIL+1))
else
  echo "PASS: frontmatter-retired file is absent from the index"; PASS=$((PASS+1))
fi

# ---- an EMPTY corpus is a successful build of nothing ---------------------
# It used to return 1. The freshness stamp is only written on success, so an
# empty memory dir was rediscovered and rebuilt at every single SessionStart,
# forever — the failure that made the freshness path look like it was working.
EMPTY="$TMP/corpus-empty"; mkdir -p "$EMPTY"
out=$("$DIR/membackend-local-embed.sh" build emptied "$EMPTY" 2>&1); rc=$?
checkrc "build of an empty corpus -> exit 0" "$rc" 0
check "build of an empty corpus reports zero chunks" "$out" "built 0 chunks"
# ...and what it wrote is a real index that health then calls UNHEALTHY, so the
# tier eager-loads instead of going slim against a corpus that answers nothing.
[ -f "$XDG_STATE_HOME/claude-memory/local-embed-emptied.json" ] \
  && { echo "PASS: empty build still wrote an index file"; PASS=$((PASS+1)); } \
  || { echo "FAIL: empty build wrote no index file"; FAIL=$((FAIL+1)); }
"$DIR/membackend-local-embed.sh" health emptied >/dev/null 2>&1; rc=$?
checkrc "health of an empty-corpus index -> exit 3" "$rc" 3

# ---- a rebuild reuses vectors for unchanged chunks -----------------------
# One edited note triggers a full rebuild. Re-embedding every chunk to absorb it
# cost 10.7s of five-core CPU on the real 279-chunk corpus; the unchanged chunks
# already have correct vectors in the index. Keyed on chunk text, so the reuse
# survives a file rename too.
REBUILD=$("$DIR/membackend-local-embed.sh" build main "$CORPUS" 2>&1)
check "rebuild embeds nothing when no text changed" "$REBUILD" "(0 embedded,"
check "rebuild reuses every chunk" "$REBUILD" "reused)"

# Adding one file must embed ONLY its chunks, not the whole corpus again.
cat > "$CORPUS/pottery.md" <<'EOF'
---
name: pottery
---
Stoneware is fired above 1200C until the clay body vitrifies and stops absorbing water.
EOF
INCR=$("$DIR/membackend-local-embed.sh" build main "$CORPUS" 2>&1)
check "adding one note embeds exactly one new chunk" "$INCR" "(1 embedded,"
# and the new note is immediately retrievable — the point of the rebuild
NEW_OUT=$("$DIR/membackend-local-embed.sh" search main "clay vitrifies when fired" 3 2>/dev/null)
check "the newly added note is retrievable" "$NEW_OUT" "pottery.md"

# A different model must NOT reuse vectors from another model's space.
python3 - "$XDG_STATE_HOME/claude-memory/local-embed-main.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["model"] = "some/other-model"
json.dump(d, open(p, "w"))
PYEOF
MIX=$("$DIR/membackend-local-embed.sh" build main "$CORPUS" 2>&1)
if printf '%s' "$MIX" | grep -q '(0 embedded,'; then
  echo "FAIL: reused vectors across a model change: $MIX"; FAIL=$((FAIL+1))
else
  echo "PASS: a model change re-embeds instead of mixing vector spaces"; PASS=$((PASS+1))
fi

# ---- an index that exists but is EMPTY is not healthy --------------------
# Phase 4 makes an empty corpus write a valid empty index and exit 0, so the
# freshness path stops rebuilding forever. A shell `-f` test reads that file as
# healthy and sends SessionStart into slim mode against an index that returns
# nothing — silent memory loss. health must look inside.
printf '{"model":"m","corpus":"%s","chunks":[]}' "$CORPUS" \
  > "$XDG_STATE_HOME/claude-memory/local-embed-hollow.json"
"$DIR/membackend-local-embed.sh" health hollow >/dev/null 2>&1; rc=$?
checkrc "health for an existing but chunk-less index -> exit 3" "$rc" 3

# ---- venv missing entirely -> exit 3, never hangs / never exit 1 ----
BOGUS_VENV="$TMP/no-such-venv"
out=$(MEMORY_VENV="$BOGUS_VENV" "$DIR/membackend-local-embed.sh" search main "q" 5 2>&1); rc=$?
checkrc "no venv -> exit 3 (fallback, not hang/error)" "$rc" 3

# ---- chunks carry entry identity, and search returns one slot per entry ---
# ERRORS.md holds ~54 dated entries and windows out to ~157 chunks under a
# single path (56% of the index, measured). Without a per-entry name, nothing
# downstream can distinguish "another window of the entry already chosen" from
# "a different entry", so one grab-bag file can spend every top-k slot.
LOADER="import importlib.util as u; sp=u.spec_from_file_location('le','$DIR/local-embed.py'); m=u.module_from_spec(sp); sp.loader.exec_module(m)"

ENTRY_OUT=$("$PY" -c "$LOADER
t='## [2026-01-01] first thing\nbody one\n\n## [2026-01-02] second thing\nbody two\n'
pairs=m.chunk_text(t)
assert all(isinstance(x, tuple) and len(x)==2 for x in pairs), 'chunk_text must yield (entry, chunk)'
ents=[e for e,_ in pairs]
print('|'.join(sorted(set(ents))))" 2>&1)
check "chunk_text names the first entry" "$ENTRY_OUT" "first thing"
check "chunk_text names the second entry" "$ENTRY_OUT" "second thing"

# A section keeps its heading only in its FIRST window, so a long entry must
# still tag every one of its windows with the same entry name — otherwise the
# later windows dedup against each other under the empty string.
LONG_OUT=$("$PY" -c "$LOADER
body='\n'.join('line %d of a deliberately long entry' % i for i in range(200))
t='## [2026-01-01] one long entry\n' + body + '\n'
pairs=m.chunk_text(t)
ents=set(e for e,_ in pairs)
print('windows=%d distinct_entries=%d' % (len(pairs), len(ents)))" 2>&1)
check "every window of one entry shares its name" "$LONG_OUT" "distinct_entries=1"

# ---- the model cache must not live in a purgeable temp dir ----------------
# fastembed defaults to $TMPDIR/fastembed_cache. macOS purges that, so the first
# recall after a purge re-downloads ~64MB INSIDE the UserPromptSubmit hook —
# measured at 4.0s cold against a 2s budget, versus 0.39s warm. The cache is
# pinned to an XDG path instead; these guard the pin and its override.
CACHE_DEFAULT=$("$PY" -c "import sys; sys.path.insert(0, '$DIR'); \
import importlib.util as u; sp=u.spec_from_file_location('le', '$DIR/local-embed.py'); \
m=u.module_from_spec(sp); sp.loader.exec_module(m); print(m.model_cache_dir())" 2>/dev/null)
case "$CACHE_DEFAULT" in
  "${TMPDIR:-/tmp}"*) checkrc "model cache is NOT under TMPDIR" 1 0 ;;
  "") checkrc "model cache dir resolvable" 1 0 ;;
  *) checkrc "model cache is NOT under TMPDIR" 0 0 ;;
esac

CACHE_OVERRIDE=$(MEMORY_MODEL_CACHE="$TMP/pinned-cache" "$PY" -c "import sys; \
import importlib.util as u; sp=u.spec_from_file_location('le', '$DIR/local-embed.py'); \
m=u.module_from_spec(sp); sp.loader.exec_module(m); print(m.model_cache_dir())" 2>/dev/null)
check "MEMORY_MODEL_CACHE overrides the cache dir" "$CACHE_OVERRIDE" "pinned-cache"

rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
