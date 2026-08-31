#!/bin/sh
# Tests for hooks/lib/episodic-recall.sh — transcript history as a recall tier.
# The CLI is stubbed via a fake plugin tree under a temp CLAUDE_CONFIG_DIR, so
# nothing here touches the real conversation archive or the real plugin.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
no() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

. "$DIR/episodic-recall.sh"

# ---- intent detection ------------------------------------------------------
# The false positives matter more than the false negatives: firing costs ~0.6s
# on the hot path and injects transcript text into a prompt that did not ask for
# it, so "before you commit" must not read as a question about the past.
for q in \
  "did we ever figure out why the health check said not ready" \
  "what did we decide about the boost ceiling" \
  "how did I fix this last month" \
  "last time this broke, what was it" \
  "remember when the index kept shrinking" \
  "we already tried pinning the cache, right" \
  "in a previous session you changed the floor" ; do
  episodic_history_intent "$q" && ok "intent: $q" || no "intent missed" "$q"
done

for q in \
  "before you commit, run the full test suite" \
  "fix the failing test in the recall hook" \
  "explain how actor isolation works in swift" \
  "add a previously unused flag to the parser" \
  "the build broke earlier in the pipeline" \
  "decide whether to keep the reranker" ; do
  episodic_history_intent "$q" && no "false positive" "$q" || ok "not history: $q"
done

# ---- fail-open: no plugin installed ---------------------------------------
TMP=$(mktemp -d)
OUT=$(CLAUDE_CONFIG_DIR="$TMP/empty-cfg" episodic_recall_block "did we ever fix this" 2)
[ -z "$OUT" ] && ok "no plugin installed -> empty, no error" \
  || no "no plugin installed" "expected empty, got: $OUT"

# ---- a well-formed CLI answer is parsed ------------------------------------
CFG="$TMP/cfg"
CLI_DIR="$CFG/plugins/cache/em-dev/episodic-memory/1.4.2/cli"
mkdir -p "$CLI_DIR"
cat > "$CLI_DIR/episodic-memory" <<'EOF'
#!/bin/sh
echo "Loading embedding model (first run may take time)..."
echo "Found 2 relevant conversations:"
echo ""
echo "1. [-Users-x-repo, 2026-08-01] - 71% match"
echo '   "the health check returned 3 because MEMBACKEND_LIB_DIR was unset"'
echo "   Lines 10-20 in /tmp/a.jsonl (1KB, 30 lines)"
echo ""
echo "2. [-Users-x-repo, 2026-07-02] - 66% match"
echo '   "we pinned the fastembed cache to an XDG path after a purge"'
echo "   Lines 40-50 in /tmp/b.jsonl (1KB, 60 lines)"
EOF
chmod +x "$CLI_DIR/episodic-memory"

OUT=$(CLAUDE_CONFIG_DIR="$CFG" episodic_recall_block "did we ever fix the health check" 2)
printf '%s' "$OUT" | grep -q '<session-history>' \
  && ok "well-formed answer produces a session-history block" \
  || no "block missing" "got: $OUT"
printf '%s' "$OUT" | grep -q 'MEMBACKEND_LIB_DIR was unset' \
  && ok "snippet text is extracted" || no "snippet missing" "got: $OUT"
printf '%s' "$OUT" | grep -q 'Loading embedding model' \
  && no "CLI chatter leaked into the block" "got: $OUT" \
  || ok "CLI progress chatter is not injected"
printf '%s' "$OUT" | grep -q 'Lines 10-20' \
  && no "file/line noise leaked into the block" "got: $OUT" \
  || ok "archive path/line noise is not injected"
# Provenance must be stated: a transcript line is not a curated memory.
printf '%s' "$OUT" | grep -qi 'not curated memory' \
  && ok "block states its provenance" || no "provenance line missing" "got: $OUT"

# ---- it must NOT run at all without history intent -------------------------
# Asserted by side effect: the stub records that it ran.
MARK="$TMP/ran"
cat > "$CLI_DIR/episodic-memory" <<EOF
#!/bin/sh
echo ran >> "$MARK"
echo "Found 1 relevant conversations:"
echo '   "something"'
EOF
chmod +x "$CLI_DIR/episodic-memory"
OUT=$(CLAUDE_CONFIG_DIR="$CFG" episodic_recall_block "fix the failing test in the recall hook" 2)
[ -f "$MARK" ] && no "CLI ran on a non-history prompt" "the hot path paid for nothing" \
  || ok "CLI is not invoked without history intent"

# ---- fail-open: unparseable output ----------------------------------------
cat > "$CLI_DIR/episodic-memory" <<'EOF'
#!/bin/sh
echo "some completely different format nobody expected"
echo "no quoted snippet lines at all"
EOF
chmod +x "$CLI_DIR/episodic-memory"
OUT=$(CLAUDE_CONFIG_DIR="$CFG" episodic_recall_block "did we ever fix this" 2)
[ -z "$OUT" ] && ok "unparseable output -> empty, not garbage" \
  || no "unparseable output" "expected empty, got: $OUT"

# ---- fail-open: a hanging CLI is killed, not waited for -------------------
# A hook that hangs blocks the user's prompt, which is worse than no history.
cat > "$CLI_DIR/episodic-memory" <<'EOF'
#!/bin/sh
sleep 30
EOF
chmod +x "$CLI_DIR/episodic-memory"
T0=$(date +%s)
OUT=$(CLAUDE_CONFIG_DIR="$CFG" EPISODIC_DEADLINE_TENTHS=5 \
      episodic_recall_block "did we ever fix this" 2)
T1=$(date +%s)
[ -z "$OUT" ] && ok "hanging CLI -> empty" || no "hanging CLI" "got: $OUT"
[ $((T1 - T0)) -lt 10 ] && ok "hanging CLI is killed at the deadline ($((T1-T0))s)" \
  || no "hanging CLI not killed" "took $((T1-T0))s"

# ---- fail-open: CLI exits non-zero ---------------------------------------
cat > "$CLI_DIR/episodic-memory" <<'EOF'
#!/bin/sh
echo "boom" >&2
exit 1
EOF
chmod +x "$CLI_DIR/episodic-memory"
OUT=$(CLAUDE_CONFIG_DIR="$CFG" episodic_recall_block "did we ever fix this" 2)
[ -z "$OUT" ] && ok "failing CLI -> empty" || no "failing CLI" "got: $OUT"

# ---- an empty prompt is not a search -------------------------------------
OUT=$(CLAUDE_CONFIG_DIR="$CFG" episodic_recall_block "" 2)
[ -z "$OUT" ] && ok "empty prompt -> empty" || no "empty prompt" "got: $OUT"

rm -rf "$TMP"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
