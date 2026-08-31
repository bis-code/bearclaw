#!/bin/sh
# Tests for stop-handoff-reminder.sh (usage-based context measurement + 60/70
# escalation). Env seams: CLAUDE_HANDOFF_STATE_DIR, CLAUDE_CONTEXT_WINDOW,
# CLAUDE_HANDOFF_START_PCT, CLAUDE_HANDOFF_BAND_PCT.
HOOK="$(dirname "$0")/stop-handoff-reminder.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }
T="$TMP/transcript.jsonl"
mkusage(){ printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' "$1" "$2"; }
run(){ printf '{"transcript_path":"%s","session_id":"%s"}' "$T" "$1" | \
  CLAUDE_HANDOFF_STATE_DIR="$TMP" CLAUDE_CONTEXT_WINDOW=1000 \
  CLAUDE_HANDOFF_START_PCT=60 CLAUDE_HANDOFF_BAND_PCT=10 sh "$HOOK"; }
# Same, but with cwd + HOME (for the roadmap-reminder guard).
runcwd(){ printf '{"transcript_path":"%s","session_id":"%s","cwd":"%s"}' "$T" "$1" "$2" | \
  HOME="$3" CLAUDE_HANDOFF_STATE_DIR="$TMP" CLAUDE_CONTEXT_WINDOW=1000 \
  CLAUDE_HANDOFF_START_PCT=60 CLAUDE_HANDOFF_BAND_PCT=10 sh "$HOOK"; }

# t1: 40% -> silent
mkusage 300 100 > "$T"
out=$(run sA); [ -z "$out" ] && ok "t1 below 60% silent" || bad "t1" "$out"

# t2: 65% -> gentle warn (mentions handoff, not NOW)
mkusage 400 250 > "$T"
out=$(run sB)
printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1 && ok "t2 warns at 65%" || bad "t2" "$out"
printf '%s' "$out" | grep -qi 'handoff' && ok "t2 names handoff" || bad "t2 name" "$out"
printf '%s' "$out" | grep -q 'NOW' && bad "t2 gentle" "urgent too early" || ok "t2 gentle wording"

# t3: still 65%, same session -> silent (same band)
out=$(run sB); [ -z "$out" ] && ok "t3 same band silent" || bad "t3" "$out"

# t4: 75% -> re-warns, urgent wording (new band)
mkusage 500 250 > "$T"
out=$(run sB)
printf '%s' "$out" | grep -q 'NOW' && ok "t4 urgent at 75%" || bad "t4" "$out"

# t5: still 75% -> silent
out=$(run sB); [ -z "$out" ] && ok "t5 urgent band once" || bad "t5" "$out"

# t6: missing transcript -> exit 0, silent
out=$(printf '{"session_id":"sC"}' | CLAUDE_HANDOFF_STATE_DIR="$TMP" CLAUDE_CONTEXT_WINDOW=1000 sh "$HOOK"); rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } && ok "t6 no transcript no-op" || bad "t6" "rc=$rc out=$out"

# t7: LAST usage entry wins (50 then 800 -> 80%, urgent for fresh session)
{ mkusage 25 25; mkusage 700 100; } > "$T"
out=$(run sD)
printf '%s' "$out" | grep -q 'NOW' && ok "t7 last entry wins" || bad "t7" "$out"

# t8: roadmap-update reminder fires for any repo with a GitHub remote.
# Use the symlink-resolved tmp root so it matches git --path-format=absolute
# (macOS /var -> /private/var); $HOME prefix match would otherwise miss.
TMP_REAL=$(cd "$TMP" && pwd -P)
mkusage 700 100 > "$T"   # 80% -> fires for a fresh session id
PROJ="$TMP_REAL/proj"; mkdir -p "$PROJ"
( cd "$PROJ" && git init -q && git config user.email t@t && git config user.name t \
    && git commit -q --allow-empty -m init \
    && git remote add origin https://example.com/proj.git )

# t8: repo with a GitHub remote -> reminder includes the issues-update line
out=$(runcwd sE "$PROJ" "$TMP_REAL")
printf '%s' "$out" | grep -q 'update your GitHub issues' \
  && ok "t8 personal repo gets issues reminder" || bad "t8" "$out"

# t10–t12 (memory-capture auto-trigger) removed (T9): the block depended on
# stop-memory-signal.sh's signal file, retired along with the review-queue
# machinery. See hooks/stop-handoff-reminder.sh.

# t13 (Q9 2026-08-17): band RESETS when context drops below the threshold —
# a /compact shrinks context; without the reset the pre-compact high band
# suppressed every post-compact warning until the old high-water was exceeded.
mkusage 500 250 > "$T"          # 75% -> band 1 stored
run sQ9 >/dev/null
mkusage 300 100 > "$T"          # 40% (post-compact) -> silent + reset
out=$(run sQ9); [ -z "$out" ] && ok "t13 post-compact below threshold silent" || bad "t13a" "$out"
mkusage 400 250 > "$T"          # 65% again (band 0) -> must WARN again
out=$(run sQ9)
printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1 \
    && ok "t13 re-warns after compact reset" || bad "t13b" "band not reset: $out"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
