#!/bin/sh
# Tests for postcompact-resume.sh — the NEUTRAL pointer (D4 2026-08-16):
# fires only after an AUTO compact AND only when a precompact snapshot exists;
# manual /compact stays silent; the old "resume immediately / do not ask"
# directive must be gone. HOME is overridden per-run so the hook's default
# ~/.claude/handoffs path never touches this machine's real handoffs.
HOOK="$(dirname "$0")/postcompact-resume.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"

run() { printf '%s' "$1" | HOME="$FAKE_HOME" sh "$HOOK"; }

# t1: manual compact -> silent, exit 0 (the whole point of the hook)
out=$(run '{"trigger":"manual"}'); rc=$?
[ "$rc" -eq 0 ] && ok "t1 manual: exits 0" || bad "t1 rc" "$rc"
[ -z "$out" ] && ok "t1 manual: silent (no pointer)" || bad "t1 manual" "$out"

# t2: auto compact but NO snapshot on disk -> silent, exit 0 (summary stands alone)
out=$(run '{"trigger":"auto"}'); rc=$?
[ "$rc" -eq 0 ] && ok "t2 auto+no-snapshot: exits 0" || bad "t2 rc" "$rc"
[ -z "$out" ] && ok "t2 auto+no-snapshot: silent" || bad "t2" "$out"

# t3: auto compact with a snapshot -> fires with a PostCompact pointer at it
mkdir -p "$FAKE_HOME/.claude/handoffs"
SNAP="$FAKE_HOME/.claude/handoffs/precompact-20260101-000000.md"
printf '# snapshot\n' > "$SNAP"
out=$(run '{"trigger":"auto"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="PostCompact"' >/dev/null 2>&1 \
  && ok "t3 auto+snapshot: emits PostCompact hookSpecificOutput" || bad "t3 shape" "$out"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qF "$SNAP" \
  && ok "t3 message points at the snapshot path" || bad "t3 path" "$out"

# t4: the old auto-resume directive is GONE (neutral pointer only)
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null \
  | grep -qiE 'without asking|do not request clarification|immediately' \
  && bad "t4" "old resume-push wording still present" || ok "t4 no resume-push wording"

# t5: mentions the path-scoped-rules re-read reminder
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'scoped rules' \
  && ok "t5 scoped-rules reminder present" || bad "t5" "$out"

# t6: missing trigger field -> treated as auto (fires when snapshot exists)
out=$(run '{}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && ok "t6 missing trigger: fires (unknown treated as auto)" || bad "t6" "$out"

# t7: multiple snapshots -> picks the most recently modified one (ls -1t | head -1).
OLDER="$FAKE_HOME/.claude/handoffs/precompact-20250101-000000.md"
printf '# older\n' > "$OLDER"
touch -t 202501010000 "$OLDER"
NEWER="$FAKE_HOME/.claude/handoffs/precompact-20301231-000000.md"
printf '# newer\n' > "$NEWER"
touch -t 203012310000 "$NEWER"
out=$(run '{"trigger":"auto"}')
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qF "$NEWER" \
  && ok "t7 multiple snapshots: picks the most recent" || bad "t7" "$out"

# t8: malformed (non-JSON) stdin -> jq lookup fails safely; hook fails open
# (fires, since a snapshot exists) rather than swallowing the pointer.
out=$(printf 'not json' | HOME="$FAKE_HOME" sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && ok "t8 malformed stdin: exits 0" || bad "t8 rc" "$rc"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && ok "t8 malformed stdin: fails open (still fires)" || bad "t8" "$out"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
