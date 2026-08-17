#!/bin/sh
# Tests for precompact-snapshot.sh — the SLIM snapshot (D4 2026-08-16) captures
# git state + todos ONLY: the old recently-edited find walk and transcript tail
# are asserted ABSENT. Also covers keep-N pruning. SNAPSHOT_DIR seam keeps
# output out of the real ~/.claude/handoffs.
HOOK="$(dirname "$0")/precompact-snapshot.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

# A workspace with a git repo, a recently-edited file, and a JSONL transcript.
WS="$TMP/ws"; mkdir -p "$WS"
( cd "$WS" && git init -q && git config user.email t@t && git config user.name t \
    && git commit -q --allow-empty -m "init commit" )
echo "edited" > "$WS/RECENT_EDIT_CANARY.txt"

T="$TMP/transcript.jsonl"
# user text, assistant text, then a TodoWrite tool_use (the LAST one wins)
printf '%s\n' '{"type":"user","message":{"role":"user","content":"please do TASK-ALPHA"}}'   >> "$T"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working on TASK-ALPHA now"}]}}' >> "$T"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"STALE-TODO","status":"completed"}]}}]}}' >> "$T"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"FRESH-TODO-XYZ","status":"in_progress"}]}}]}}' >> "$T"

OUTDIR="$TMP/out"; mkdir -p "$OUTDIR"
printf '{"cwd":"%s","transcript_path":"%s"}\n' "$WS" "$T" \
  | SNAPSHOT_DIR="$OUTDIR" sh "$HOOK" >/dev/null 2>&1
rc=$?
SNAP=$(ls "$OUTDIR"/precompact-*.md 2>/dev/null | head -1)

[ "$rc" -eq 0 ] && ok "t0 exits 0" || bad "t0 rc" "$rc"
[ -n "$SNAP" ] && ok "t1 snapshot file written" || { bad "t1" "no snapshot file"; echo "SOME FAILED"; exit 1; }

grep -q "FRESH-TODO-XYZ" "$SNAP" && ok "t2 captures last TodoWrite" || bad "t2" "fresh todo missing"
grep -q "STALE-TODO" "$SNAP" && bad "t3" "older TodoWrite leaked (should be last-only)" || ok "t3 only last TodoWrite kept"
# D4 slim assertions: the find-walk SECTION and transcript tail are GONE.
# (grep the section headers, not the canary filename — an untracked canary
# legitimately shows up in the git-status Working tree block.)
grep -q "## Recently edited" "$SNAP" && bad "t4" "recently-edited section still present (D4 removed it)" || ok "t4 no recently-edited walk"
grep -q "TASK-ALPHA" "$SNAP" && bad "t5" "transcript tail still present (D4 removed it)" || ok "t5 no transcript tail"
grep -q "init commit" "$SNAP" && ok "t6 still captures git log" || bad "t6" "git log missing"

# No transcript path -> still writes a file, todos gracefully empty, exit 0
printf '{"cwd":"%s"}\n' "$WS" | SNAPSHOT_DIR="$TMP/out2" sh "$HOOK" >/dev/null 2>&1; rc2=$?
[ "$rc2" -eq 0 ] && ok "t7 no-transcript exits 0" || bad "t7" "$rc2"

# t8: pruning — pre-seed KEEP+2 old snapshots with pinned mtimes; after one run
# only SNAPSHOT_KEEP files remain and the survivors are the newest ones.
PRUNE="$TMP/prune"; mkdir -p "$PRUNE"
i=1
while [ "$i" -le 5 ]; do
    f="$PRUNE/precompact-2025010100000$i.md"
    printf '# old %s\n' "$i" > "$f"
    touch -t "20250101000$(printf '%02d' "$i")" "$f"
    i=$((i + 1))
done
printf '{"cwd":"%s"}\n' "$WS" | SNAPSHOT_DIR="$PRUNE" SNAPSHOT_KEEP=3 sh "$HOOK" >/dev/null 2>&1
COUNT=$(ls -1 "$PRUNE"/precompact-*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -eq 3 ] && ok "t8 pruning keeps SNAPSHOT_KEEP files (got $COUNT)" || bad "t8" "expected 3 files, got $COUNT"
# the file the run just wrote must be among the survivors (newest kept)
NEWEST=$(ls -1t "$PRUNE"/precompact-*.md 2>/dev/null | head -1)
grep -q "Pre-compact auto-snapshot" "$NEWEST" && ok "t9 newest survivor is the fresh snapshot" || bad "t9" "fresh snapshot pruned"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
