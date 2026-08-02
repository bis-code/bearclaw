#!/usr/bin/env bash
# SessionStart self-heal for settings.json (§6.5 durable-symlink fix).
#
# Claude Code atomic-writes the active config root's settings.json (temp+rename)
# on /config, /effort, and plugin changes. The rename replaces the repo SYMLINK
# with a REAL FILE and drops repo-only keys (effortLevel observed lost). This
# hook runs at session start, detects the clobber, MERGES the live file's keys
# back into the repo's canonical settings.json (no loss), and re-asserts the
# symlink. Idempotent — a no-op when the symlink is already intact.
#
# settings.json is shared across config roots via symlink (work -> ~/.claude ->
# repo); .mcp.json and auth are per-root and are NEVER touched here.
#
# Env seams (for tests):
#   CLAUDE_SETUP_REPO  (default: resolved from this hook's own location)
#   CLAUDE_CONFIG_DIR  (default $HOME/.claude) — the active config root
set -uo pipefail

REPO="${CLAUDE_SETUP_REPO:-$(CDPATH= cd -P "$(dirname "$0")" && cd .. && pwd)}"
CANON="$REPO/settings.json"
ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LIVE="$ROOT/settings.json"

# Nothing to heal against if the canonical file is gone.
[ -f "$CANON" ] || exit 0

# Fast path: a symlink that still resolves is fine (covers the work -> personal
# -> repo chain). Only a real-file clobber or a broken symlink needs healing.
if [ -L "$LIVE" ] && [ -e "$LIVE" ]; then exit 0; fi

resymlink() { rm -f "$LIVE"; ln -s "$CANON" "$LIVE"; }

if [ -f "$LIVE" ] && [ ! -L "$LIVE" ]; then
  # Real-file clobber. Merge so nothing is lost:
  #   jq '.[0] * .[1]'  → canonical keys preserved, LIVE values win on overlap,
  #   LIVE-only (new /config) keys added. Restores effortLevel (repo-only,
  #   dropped by the clobber) while keeping the user's latest /config change.
  command -v jq >/dev/null 2>&1 || exit 0   # never risk a blind overwrite
  tmp="$(mktemp)"
  if jq -s '.[0] * .[1]' "$CANON" "$LIVE" >"$tmp" 2>/dev/null && [ -s "$tmp" ] && jq empty "$tmp" 2>/dev/null; then
    cp "$tmp" "$CANON"
    resymlink
    printf '{"systemMessage":"settings.json self-heal: re-symlinked %s -> repo and merged live keys back (no loss). Review/commit repo settings.json."}\n' "$LIVE"
  fi
  rm -f "$tmp"
elif [ ! -e "$LIVE" ]; then
  # Broken or missing symlink — nothing to preserve, just re-assert it.
  resymlink
  printf '{"systemMessage":"settings.json self-heal: re-symlinked %s -> repo."}\n' "$LIVE"
fi
exit 0
