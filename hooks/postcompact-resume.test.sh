#!/bin/sh
# Tests for postcompact-resume.sh — injects a resume instruction after an
# AUTO compact only ("trigger":"auto", or missing/unknown treated as auto);
# a manual /compact ("trigger":"manual") must stay silent so the user drives
# the next turn themselves. Also covers the precompact-snapshot pointer line,
# which only appears when a snapshot file exists under ~/.claude/handoffs.
# HOME is overridden per-run so the hook's hardcoded ~/.claude/handoffs path
# never touches this machine's real handoffs.
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
[ -z "$out" ] && ok "t1 manual: silent (no resume directive)" || bad "t1 manual" "$out"

# t2: auto compact -> fires with a PostCompact resume directive
out=$(run '{"trigger":"auto"}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="PostCompact"' >/dev/null 2>&1 \
  && ok "t2 auto: emits PostCompact hookSpecificOutput" || bad "t2 shape" "$out"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qi 'auto-compacted' \
  && ok "t2 auto: mentions auto-compaction" || bad "t2 msg" "$out"

# t3: missing trigger field -> treated as auto (fires, not silent)
out=$(run '{}')
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && ok "t3 missing trigger: fires (unknown treated as auto)" || bad "t3" "$out"

# t4: no precompact snapshot on disk -> message has no snapshot pointer line
out=$(run '{"trigger":"auto"}')
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'pre-compact git/repo snapshot' \
  && bad "t4" "snapshot line present with no snapshot file" || ok "t4 no snapshot file: no snapshot line"

# t5: a precompact snapshot exists -> message points at it by path
mkdir -p "$FAKE_HOME/.claude/handoffs"
SNAP="$FAKE_HOME/.claude/handoffs/precompact-20260101-000000.md"
printf '# snapshot\n' > "$SNAP"
out=$(run '{"trigger":"auto"}')
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qF "$SNAP" \
  && ok "t5 snapshot present: message points at the snapshot path" || bad "t5" "$out"

# t6: multiple snapshots -> picks the most recently modified one (ls -1t | head -1).
# Timestamps are pinned far apart with `touch -t` so ordering never depends on
# wall-clock timing between file creations.
OLDER="$FAKE_HOME/.claude/handoffs/precompact-20250101-000000.md"
printf '# older\n' > "$OLDER"
touch -t 202501010000 "$OLDER"
NEWER="$FAKE_HOME/.claude/handoffs/precompact-20301231-000000.md"
printf '# newer\n' > "$NEWER"
touch -t 203012310000 "$NEWER"
out=$(run '{"trigger":"auto"}')
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qF "$NEWER" \
  && ok "t6 multiple snapshots: picks the most recent" || bad "t6" "$out"

# t7: malformed (non-JSON) stdin -> jq trigger lookup fails safely; hook still
# fires (fails open) rather than silently swallowing the resume directive.
out=$(printf 'not json' | HOME="$FAKE_HOME" sh "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && ok "t7 malformed stdin: exits 0" || bad "t7 rc" "$rc"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && ok "t7 malformed stdin: fails open (still fires)" || bad "t7" "$out"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
