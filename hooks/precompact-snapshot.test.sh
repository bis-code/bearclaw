#!/bin/sh
# Tests for precompact-snapshot.sh — the enriched snapshot must capture todos,
# recently-edited files, and a transcript tail (not just git state). SNAPSHOT_DIR
# seam keeps output out of the real ~/.claude/handoffs.
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
grep -q "RECENT_EDIT_CANARY.txt" "$SNAP" && ok "t4 lists recently-edited file" || bad "t4" "recent file missing"
grep -q "TASK-ALPHA" "$SNAP" && ok "t5 captures transcript tail text" || bad "t5" "tail text missing"
grep -q "init commit" "$SNAP" && ok "t6 still captures git log" || bad "t6" "git log missing"

# No transcript path -> still writes a file, todos/tail gracefully empty, exit 0
printf '{"cwd":"%s"}\n' "$WS" | SNAPSHOT_DIR="$TMP/out2" sh "$HOOK" >/dev/null 2>&1; rc2=$?
mkdir -p "$TMP/out2" 2>/dev/null
[ "$rc2" -eq 0 ] && ok "t7 no-transcript exits 0" || bad "t7" "$rc2"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
