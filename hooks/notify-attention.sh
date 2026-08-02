#!/bin/sh
# notify-attention.sh — Notification hook (user scope, all projects).
#
# Fires a desktop notification ONLY when Claude Code genuinely needs you, and
# labels WHICH kind of "needs you" it is. The Notification event carries a
# `notification_type` discriminator — the hook branches on it instead of firing
# on everything (the old behaviour, which pinged "needs your input" even for
# agent-dispatch permission prompts that aren't really waiting on you):
#
#   idle_prompt        -> "✋ ..." (Glass)  — turn ended, truly waiting for you
#   permission_prompt  -> "🔐 ..." (Ping)   — a tool/agent wants to proceed
#   auth_success       -> silent            — no attention needed
#   elicitation_*      -> silent            — MCP form lifecycle, not for you
#   (missing/unknown)  -> "🔔 ..." (Glass)  — fire generic; never drop a real one
#
# Icon: delivery is via the stock terminal-notifier, branded with Claude's icon +
# "Claude Code" name by bin/brand-notifier.sh (left icon, all states). The
# per-state glyph rides along as a right-side thumbnail via -contentImage. We do
# NOT use a custom .app per state — ad-hoc-signed clones lose macOS-26 notification
# authorization on reboot. Falls back to plain osascript without terminal-notifier,
# then a silent no-op on non-macOS.
#
# No click handler: terminal-notifier's -execute/-activate/-wait are all dead on
# macOS 26 (the NSUserNotification interactivity layer was removed), so a click
# can't be wired from a CLI notifier. macOS-26 gotchas, all avoided here: -sender
# hangs; -appIcon ignored; -execute/-activate no-op.
#
# Always exits 0; never blocks. The .message text is passed to terminal-notifier /
# osascript via argv (NOT string-interpolated) so quotes/backticks can't inject.
#
# Test seam: CLAUDE_NOTIFY_LOG, when set, captures "title<TAB>subtitle<TAB>message"
# to that file instead of delivering — lets tests assert without popping notifications.

set +e

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

NTYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
MSG=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Branch on the notification type: pick an emoji marker, sound, default text, and
# the custom-icon basename (an optional PNG thumbnail per state — see ICON below).
# Silent types return before doing any work.
case "$NTYPE" in
    idle_prompt)
        EMOJI="✋"; SOUND="Glass"; ICONNAME="notify-waiting"
        [ -n "$MSG" ] || MSG="Waiting for your input"
        ;;
    permission_prompt)
        EMOJI="🔐"; SOUND="Ping"; ICONNAME="notify-approval"
        [ -n "$MSG" ] || MSG="Needs your approval"
        ;;
    auth_success|elicitation_dialog|elicitation_complete|elicitation_response)
        exit 0
        ;;
    *)
        # Missing or unknown type: don't silently swallow a genuine attention
        # signal — fire a neutral notification.
        EMOJI="🔔"; SOUND="Glass"; ICONNAME="notify-attention"
        [ -n "$MSG" ] || MSG="Claude needs your attention"
        ;;
esac
MSG="$EMOJI $MSG"

# Per-state glyph as a right-side thumbnail (-contentImage). We deliver via the
# stock terminal-notifier, NOT a custom .app: ad-hoc-signed clones lose macOS-26
# notification authorization on reboot and silently stop delivering. Stock
# terminal-notifier is a stable installed app and always delivers; -contentImage
# still renders the custom glyph. Absent PNG -> no thumbnail, still delivers.
ICON_DIR="${CLAUDE_NOTIFY_ICON_DIR:-$HOME/.claude/assets}"
ICON="$ICON_DIR/$ICONNAME.png"
[ -f "$ICON" ] || ICON=""

# Resolve transcript (prefer stdin, else find by session id) so we can read the
# session's human name.
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    [ -n "$SID" ] && TRANSCRIPT=$(find "$HOME/.claude/projects" -maxdepth 3 -name "${SID}.jsonl" -type f 2>/dev/null | head -1)
fi

# Session name = what YOU called this chat: /rename's custom-title, else the
# auto-generated ai-title. Both are transcript entries keyed by sessionId.
NAME=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    NAME=$(grep '"type":"custom-title"' "$TRANSCRIPT" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
    [ -n "$NAME" ] || NAME=$(grep '"type":"ai-title"' "$TRANSCRIPT" 2>/dev/null | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null)
fi

# Context pieces: project (cwd basename), git branch, short session id.
PROJECT="Claude Code"
[ -n "$CWD" ] && PROJECT=$(basename "$CWD")
BR=""
[ -n "$CWD" ] && BR=$(git -C "$CWD" branch --show-current 2>/dev/null)
SHORT=""
[ -n "$SID" ] && SHORT=$(printf '%s' "$SID" | cut -c1-8)

# Title = session name (which chat); fall back to project. Subtitle carries the
# remaining context so parallel sessions are always distinguishable.
if [ -n "$NAME" ]; then
    TITLE="$NAME"
    SUB="$PROJECT"
else
    TITLE="$PROJECT"
    SUB=""
fi
[ -n "$BR" ] && SUB="${SUB:+$SUB · }$BR"
[ -n "$SHORT" ] && SUB="${SUB:+$SUB · }#$SHORT"

if [ -n "$CLAUDE_NOTIFY_LOG" ]; then
    printf '%s\t%s\t%s\n' "$TITLE" "$SUB" "$MSG" >> "$CLAUDE_NOTIFY_LOG" 2>/dev/null
    exit 0
fi

if command -v terminal-notifier >/dev/null 2>&1; then
    # Stock terminal-notifier (reliable; Claude-branded via brand-notifier.sh).
    # -contentImage adds the per-state glyph. No -timeout (notification persists
    # in Notification Center until dismissed); no click handler (dead on macOS 26).
    # Args are argv (no shell eval) -> injection-safe.
    set -- -title "$TITLE" -subtitle "$SUB" -message "$MSG" -sound "$SOUND"
    [ -n "$ICON" ] && set -- "$@" -contentImage "$ICON"
    terminal-notifier "$@" >/dev/null 2>&1 &
elif command -v osascript >/dev/null 2>&1; then
    # argv-passed (items of argv), never interpolated -> injection-safe.
    osascript \
        -e 'on run argv' \
        -e 'display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv) sound name (item 4 of argv)' \
        -e 'end run' \
        "$TITLE" "$SUB" "$MSG" "$SOUND" >/dev/null 2>&1 &
fi

exit 0
