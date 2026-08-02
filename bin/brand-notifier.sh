#!/bin/sh
# brand-notifier.sh — give the stock terminal-notifier a Claude identity so
# attention notifications show Claude's icon + "Claude Code" header instead of
# the generic terminal icon.
#
# WHY in-place on the stock app (not a custom clone): on macOS 26 a notification's
# left icon + group header come from the POSTING app, and only an app already
# AUTHORIZED for notifications delivers reliably. Ad-hoc-signed clones lose that
# authorization on reboot and silently stop delivering (learned the hard way —
# see memory-global/ERRORS.md). The stock terminal-notifier is already authorized,
# so we rebrand IT: swap Contents/Resources/Terminal.icns + CFBundleName, and do
# NOT re-sign (re-signing changes identity and can drop the grant; only the
# resource seal breaks, which macOS tolerates for this already-trusted app).
#
# Idempotent. A `brew upgrade terminal-notifier` reverts the bundle — just re-run
# this. Override the icon with $1 or CLAUDE_NOTIFY_BRAND_ICON (a .icns or .png).
set -eu

ICON_SRC="${1:-${CLAUDE_NOTIFY_BRAND_ICON:-/Applications/Claude.app/Contents/Resources/electron.icns}}"
NAME="Claude Code"

TN_BIN=$(command -v terminal-notifier 2>/dev/null) || { echo "terminal-notifier not installed (brew install terminal-notifier)"; exit 1; }
TN_REAL=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$TN_BIN")
case "$TN_REAL" in
  *.app/Contents/MacOS/*) TN_APP=$(printf '%s' "$TN_REAL" | sed 's#/Contents/MacOS/.*##') ;;
  *) TN_APP=$(find "$(dirname "$(dirname "$TN_REAL")")" -maxdepth 2 -name 'terminal-notifier.app' -type d 2>/dev/null | head -1) ;;
esac
[ -n "${TN_APP:-}" ] && [ -d "$TN_APP" ] || { echo "could not locate terminal-notifier.app"; exit 1; }
[ -f "$ICON_SRC" ] || { echo "icon not found: $ICON_SRC"; exit 1; }
echo "branding: $TN_APP"

RES="$TN_APP/Contents/Resources"
PLIST="$TN_APP/Contents/Info.plist"

# Back up the pristine originals once (so the brand is reversible).
[ -f "$RES/Terminal.icns.orig" ] || cp "$RES/Terminal.icns" "$RES/Terminal.icns.orig"
[ -f "$PLIST.orig" ] || cp "$PLIST" "$PLIST.orig"

# Convert PNG -> icns if needed; .icns copies straight in.
case "$ICON_SRC" in
  *.icns) cp "$ICON_SRC" "$RES/Terminal.icns" ;;
  *)
    iconset=$(mktemp -d)/AppIcon.iconset; mkdir -p "$iconset"
    for sz in 16 32 64 128 256 512; do sips -z "$sz" "$sz" "$ICON_SRC" --out "$iconset/icon_${sz}x${sz}.png" >/dev/null 2>&1; done
    sips -z 1024 1024 "$ICON_SRC" --out "$iconset/icon_512x512@2x.png" >/dev/null 2>&1
    iconutil -c icns "$iconset" -o "$RES/Terminal.icns"
    rm -rf "$(dirname "$iconset")"
    ;;
esac
plutil -replace CFBundleName -string "$NAME" "$PLIST"

# Refresh Launch Services + the icon/notification caches so the change shows.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$TN_APP" 2>/dev/null || true
touch "$TN_APP"
killall NotificationCenter 2>/dev/null || true

echo "done — terminal-notifier now posts as \"$NAME\" with $(basename "$ICON_SRC")."
echo "test: printf '{\"notification_type\":\"idle_prompt\",\"message\":\"hi\",\"cwd\":\"\$PWD\"}' | ~/.claude/hooks/notify-attention.sh"
