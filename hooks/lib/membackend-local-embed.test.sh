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

# health also exits 3 with no index present
out=$("$DIR/membackend-local-embed.sh" health 2>&1); rc=$?
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

BUILD_OUT=$("$PY" "$DIR/local-embed.py" build --corpus "$CORPUS" 2>&1); rc=$?
checkrc "build exits 0" "$rc" 0
check "build reports a chunk count" "$BUILD_OUT" "built [0-9][0-9]* chunks"

# ---- health now reports OK (exit 0) ----
"$DIR/membackend-local-embed.sh" health >/dev/null 2>&1; rc=$?
checkrc "health with index present -> exit 0" "$rc" 0

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

# ---- dedup: embeds the candidate file, returns nearest via the same search path
CAND="$TMP/cand.txt"
printf 'a relational store keeps rows in tables and answers queries' > "$CAND"
DEDUP_OUT=$("$DIR/membackend-local-embed.sh" dedup main "$CAND" 2>/dev/null); rc=$?
checkrc "dedup exits 0" "$rc" 0
check "dedup nearest hit is databases.md" "$DEDUP_OUT" "databases.md"

# dedup on a missing candidate file -> exit 1 (real error, not fallback)
"$DIR/membackend-local-embed.sh" dedup main "$TMP/does-not-exist.txt" >/dev/null 2>&1; rc=$?
checkrc "dedup missing candidate file -> exit 1" "$rc" 1

# ---- venv missing entirely -> exit 3, never hangs / never exit 1 ----
BOGUS_VENV="$TMP/no-such-venv"
out=$(MEMORY_VENV="$BOGUS_VENV" "$DIR/membackend-local-embed.sh" search main "q" 5 2>&1); rc=$?
checkrc "no venv -> exit 3 (fallback, not hang/error)" "$rc" 3

rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
