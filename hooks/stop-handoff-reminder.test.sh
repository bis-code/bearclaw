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

# ── Memory-capture auto-trigger tests ────────────────────────────────────────
# Uses MEMORY_STORE_DIR seam. Signal file at $STORE/_pending/signals/<sid>.jsonl.
MEM_STORE="$TMP/mem-store"
mkdir -p "$MEM_STORE/_pending/signals"

run_cap() {
    # run_cap <session-id> <signal-file-content-or-empty>
    sid="$1"; sig="$2"
    if [ -n "$sig" ]; then
        printf '%s\n' "$sig" > "$MEM_STORE/_pending/signals/${sid}.jsonl"
    else
        rm -f "$MEM_STORE/_pending/signals/${sid}.jsonl"
    fi
    printf '{"transcript_path":"%s","session_id":"%s"}' "$T" "$sid" | \
      CLAUDE_HANDOFF_STATE_DIR="$TMP" CLAUDE_CONTEXT_WINDOW=1000 \
      CLAUDE_HANDOFF_START_PCT=60 CLAUDE_HANDOFF_BAND_PCT=10 \
      MEMORY_STORE_DIR="$MEM_STORE" sh "$HOOK"
}

# t10: PCT>=60 + non-empty signal file + no marker -> decision:block, mentions capture
mkusage 400 250 > "$T"   # 65%
out=$(run_cap sCAP '{"signal":"test"}')
printf '%s' "$out" | jq -e '.decision=="block"' >/dev/null 2>&1 \
    && ok "t10 capture block fires" || bad "t10 block" "$out"
printf '%s' "$out" | jq -r '.reason' 2>/dev/null | grep -qi 'capture' \
    && ok "t10 reason mentions capture" || bad "t10 reason" "$out"
[ -f "$TMP/capture-triggered-sCAP" ] \
    && ok "t10 marker written" || bad "t10 marker" "file not found"

# t11: second run same session (marker present) -> NO block, falls through to systemMessage
out=$(run_cap sCAP '{"signal":"test"}')
printf '%s' "$out" | jq -e '.decision=="block"' >/dev/null 2>&1 \
    && bad "t11 marker-gate" "still blocking on second run" || ok "t11 marker prevents second block"
printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1 \
    && ok "t11 falls through to handoff systemMessage" || bad "t11 fallthrough" "$out"

# t12: PCT>=60 + NO signal file -> no capture block, existing handoff systemMessage emitted
out=$(run_cap sQUIET '')
printf '%s' "$out" | jq -e '.decision=="block"' >/dev/null 2>&1 \
    && bad "t12 quiet" "capture fired with no signal file" || ok "t12 quiet session no capture"
printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1 \
    && ok "t12 quiet session still gets handoff reminder" || bad "t12 handoff" "$out"
# ─────────────────────────────────────────────────────────────────────────────

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
