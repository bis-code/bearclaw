#!/usr/bin/env bash
# SessionStart self-heal for settings.json (revised for copy-on-install).
#
# Before copy-on-install, ~/.claude/settings.json was a symlink to the repo's
# canonical copy, so a Claude Code atomic-write (temp+rename) on /config,
# /effort, or a plugin change replaced the symlink with a real file and
# dropped repo-only keys. Now that install.sh COPIES settings.json instead of
# symlinking it, LIVE and CANON are always two independent real files — there
# is no symlink to clobber, and nothing this hook does can lose a key by
# having the CLI write through it.
#
# The hook's job is simpler as a result: live differs from repo canonical on
# an ALLOWLISTED key -> merge live's value into the repo canonical, so the
# next commit captures it. Any other top-level key that differs (permissions,
# env, hooks, or anything not on the allowlist) is left alone and logged as
# skipped — never merged. This is a deliberate allowlist, not a denylist: a
# denylist only catches keys someone already thought to name.
#
# Env seams (for tests):
#   CLAUDE_SETUP_REPO  (default: resolved from this hook's own location)
#   CLAUDE_CONFIG_DIR  (default $HOME/.claude) — the active config root
set -uo pipefail

REPO="${CLAUDE_SETUP_REPO:-$(CDPATH= cd -P "$(dirname "$0")" && cd .. && pwd)}"
CANON="$REPO/settings.json"
ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LIVE="$ROOT/settings.json"

# The hook is registered on SessionStart AND on Stop/StopFailure/ConfigChange.
# Stop's stdout contract is not SessionStart's, so the non-SessionStart
# registrations set SETTINGS_HEAL_SILENT=1 and every repair runs without
# emitting anything.
say() { [ -n "${SETTINGS_HEAL_SILENT:-}" ] && return 0; printf "$@"; }

# Minimal audit trail. One line per non-trivial outcome only — the quiet pass
# stays silent, so this file grows slowly.
heal_log() {
  _d="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"
  mkdir -p "$_d" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$_d/settings-heal.log" 2>/dev/null
  return 0
}

# Nothing to merge if either side is missing, or without jq (never risk a
# blind overwrite).
[ -f "$CANON" ] || exit 0
[ -f "$LIVE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
jq empty "$CANON" >/dev/null 2>&1 || exit 0
jq empty "$LIVE" >/dev/null 2>&1 || exit 0

# Keys the CLI legitimately owns and that are safe to fold back into the repo
# canonical file. Everything else — most importantly permissions (any
# subkey), env, and hooks — is NEVER merged, regardless of what shows up here.
ALLOW="enabledPlugins extraKnownMarketplaces theme model effortLevel statusLine editorMode autoCompactEnabled autoCompactWindow voiceEnabled preferredNotifChannel"

is_allowed() {
  _k="$1"
  for _a in $ALLOW; do
    [ "$_k" = "$_a" ] && return 0
  done
  return 1
}

tmp="$(mktemp)"
cp "$CANON" "$tmp"

changed=""
skipped=""
for k in $(jq -r 'keys[]' "$LIVE" 2>/dev/null); do
  live_val="$(jq -c --arg k "$k" '.[$k]' "$LIVE" 2>/dev/null)"
  canon_val="$(jq -c --arg k "$k" '.[$k] // null' "$CANON" 2>/dev/null)"
  [ "$live_val" = "$canon_val" ] && continue

  if is_allowed "$k"; then
    tmp2="$(mktemp)"
    if jq --arg k "$k" --argjson v "$live_val" '.[$k]=$v' "$tmp" >"$tmp2" 2>/dev/null \
       && [ -s "$tmp2" ] && jq empty "$tmp2" 2>/dev/null; then
      mv "$tmp2" "$tmp"
      changed="$changed $k"
    else
      rm -f "$tmp2"
    fi
  else
    skipped="$skipped $k"
  fi
done

if [ -n "$changed" ]; then
  cp "$tmp" "$CANON"
  heal_log "merged$changed (from $LIVE)"
  say '{"systemMessage":"settings.json self-heal: merged live key(s)%s from %s into repo canonical (allowlisted only). Review/commit repo settings.json."}\n' "$changed" "$LIVE"
fi
if [ -n "$skipped" ]; then
  heal_log "skipped$skipped (not in merge allowlist: permissions/env/hooks or unlisted)"
fi
rm -f "$tmp"
exit 0
