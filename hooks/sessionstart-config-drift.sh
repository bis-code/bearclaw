#!/bin/sh
# sessionstart-config-drift.sh — SessionStart hook: once-daily nudge when the
# claude-setup repo carries uncommitted or unpushed changes to the SYNCED
# surfaces (memory-global/, settings.json, rules/, CLAUDE.md) — i.e. state the
# other machine will NOT see until commit+push. The single best two-machine
# sync fix (MEM 4.x): lessons captured here otherwise strand silently.
# Throttle: one nudge per calendar day via a state stamp.
# Seams (tests): CLAUDE_SETUP_REPO, XDG_STATE_HOME, DRIFT_FORCE=1 (skip throttle).
set +e

REPO="${CLAUDE_SETUP_REPO:-}"
if [ -z "$REPO" ]; then
  CM="$(readlink -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md" 2>/dev/null)"
  [ -n "$CM" ] && REPO="$(dirname "$CM")"
fi
[ -n "$REPO" ] && [ -d "$REPO/.git" ] || exit 0

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"
mkdir -p "$STATE" 2>/dev/null
STAMP="$STATE/config-drift.$(date +%Y-%m-%d)"
if [ "${DRIFT_FORCE:-0}" != "1" ]; then
  [ -f "$STAMP" ] && exit 0
fi
: > "$STAMP" 2>/dev/null
# prune old day-stamps
find "$STATE" -maxdepth 1 -name 'config-drift.*' ! -name "$(basename "$STAMP")" -delete 2>/dev/null

DIRTY=$(git -C "$REPO" status --porcelain -- memory-global settings.json rules CLAUDE.md 2>/dev/null | head -5)
NDIRTY=$(printf '%s' "$DIRTY" | grep -c . 2>/dev/null)
AHEAD=$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)

[ "${NDIRTY:-0}" -eq 0 ] && [ "${AHEAD:-0}" -eq 0 ] && exit 0

MSG="## claude-setup sync drift
"
if [ "${NDIRTY:-0}" -gt 0 ]; then
  MSG="${MSG}$NDIRTY uncommitted change(s) on synced surfaces (memory-global/settings/rules/CLAUDE.md):
$DIRTY
"
fi
[ "${AHEAD:-0}" -gt 0 ] && MSG="${MSG}$AHEAD unpushed commit(s) — the other machine cannot see them.
"
MSG="${MSG}Commit + push (or run bin/claude-setup-sync on the other machine after). Nudged once/day."

jq -n --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
