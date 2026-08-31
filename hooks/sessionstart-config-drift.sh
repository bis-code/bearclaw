#!/bin/sh
# sessionstart-config-drift.sh — SessionStart hook: once-daily nudge when the
# claude-setup repo carries uncommitted or unpushed changes to the SYNCED
# surfaces (memory-global/, settings.json, rules/, CLAUDE.md) — i.e. state the
# other machine will NOT see until commit+push. The single best two-machine
# sync fix: lessons captured here otherwise strand silently.
#
# Also nudges (separately throttled) when the repo has moved past what's
# actually installed into the config root: install.sh copies rather than
# symlinks, so a `git pull` no longer takes effect until install.sh re-runs —
# compares $CLAUDE_CONFIG_DIR/.installed-from's sha against the repo's HEAD.
#
# Throttle: one nudge per calendar day per check, via separate state stamps.
# Seams (tests): CLAUDE_SETUP_REPO, CLAUDE_CONFIG_DIR, XDG_STATE_HOME, DRIFT_FORCE=1 (skip throttle).
set +e

ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO="${CLAUDE_SETUP_REPO:-}"
if [ -z "$REPO" ] && [ -f "$ROOT/.installed-from" ]; then
  REPO="$(sed -n 's/^repo=//p' "$ROOT/.installed-from" | head -1)"
fi
# -e, not -d: a git WORKTREE's .git is a plain file, not a directory.
[ -n "$REPO" ] && [ -e "$REPO/.git" ] || exit 0

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"
mkdir -p "$STATE" 2>/dev/null

# --- staleness check: installed copy behind the repo (own throttle) --------
STALE_LINE=""
STALE_STAMP="$STATE/config-drift-stale.$(date +%Y-%m-%d)"
if [ "${DRIFT_FORCE:-0}" = "1" ] || [ ! -f "$STALE_STAMP" ]; then
  : > "$STALE_STAMP" 2>/dev/null
  find "$STATE" -maxdepth 1 -name 'config-drift-stale.*' ! -name "$(basename "$STALE_STAMP")" -delete 2>/dev/null
  if [ -f "$ROOT/.installed-from" ]; then
    INSTALLED_SHA="$(sed -n 's/^sha=//p' "$ROOT/.installed-from" | head -1)"
    HEAD_SHA="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
    if [ -n "$INSTALLED_SHA" ] && [ -n "$HEAD_SHA" ] && [ "$INSTALLED_SHA" != "$HEAD_SHA" ]; then
      STALE_LINE="claude-setup: repo is ahead of the installed copy — run install.sh"
    fi
  fi
fi

# --- dirty/unpushed check (own throttle) ------------------------------------
STAMP="$STATE/config-drift.$(date +%Y-%m-%d)"
DO_DIRTY_CHECK=1
if [ "${DRIFT_FORCE:-0}" != "1" ] && [ -f "$STAMP" ]; then
  DO_DIRTY_CHECK=0
fi
if [ "$DO_DIRTY_CHECK" -eq 1 ]; then
  : > "$STAMP" 2>/dev/null
  # prune old day-stamps
  find "$STATE" -maxdepth 1 -name 'config-drift.*' ! -name "$(basename "$STAMP")" -delete 2>/dev/null
fi

NDIRTY=0; AHEAD=0; DIRTY=""
if [ "$DO_DIRTY_CHECK" -eq 1 ]; then
  DIRTY=$(git -C "$REPO" status --porcelain -- memory-global settings.json rules CLAUDE.md 2>/dev/null | head -5)
  NDIRTY=$(printf '%s' "$DIRTY" | grep -c . 2>/dev/null)
  AHEAD=$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
fi

[ "${NDIRTY:-0}" -eq 0 ] && [ "${AHEAD:-0}" -eq 0 ] && [ -z "$STALE_LINE" ] && exit 0

MSG="## claude-setup sync drift
"
if [ "${NDIRTY:-0}" -gt 0 ]; then
  MSG="${MSG}$NDIRTY uncommitted change(s) on synced surfaces (memory-global/settings/rules/CLAUDE.md):
$DIRTY
"
fi
[ "${AHEAD:-0}" -gt 0 ] && MSG="${MSG}$AHEAD unpushed commit(s) — the other machine cannot see them.
"
[ -n "$STALE_LINE" ] && MSG="${MSG}${STALE_LINE}
"
MSG="${MSG}Commit + push (or run bin/claude-setup-sync on the other machine after). Nudged once/day."

jq -n --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
