#!/bin/sh
# stop-handoff-reminder.sh — runs from Stop hook (user scope, all projects).
#
# Warns the user (via systemMessage) when the current session transcript has
# grown past 50% of the effective autoCompactWindow, so they have headroom
# to run /handoff manually before auto-compact strips the conversation.
#
# Threshold is computed dynamically from settings — never hardcoded — so it
# stays correct if autoCompactWindow is changed.
#
# Always exits 0 — Stop completion must never be blocked by this hook.

set +e

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"

# Resolve transcript path: prefer stdin, else search by session_id.
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    if [ -n "$SESSION_ID" ]; then
        TRANSCRIPT=$(find "$HOME/.claude/projects" -maxdepth 3 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
    fi
fi
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# Resolve settings via the user-tier cascade (project local → project → user).
# Mirrors Claude Code's own precedence closely enough that warnings fire at
# the right boundary in practice.
setting() {
    key="$1"; default="$2"
    for f in ".claude/settings.local.json" ".claude/settings.json" "$HOME/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
        [ -f "$f" ] || continue
        v=$(jq -r --arg k "$key" '.[$k] // empty' "$f" 2>/dev/null)
        [ -n "$v" ] && [ "$v" != "null" ] && { printf '%s' "$v"; return; }
    done
    printf '%s' "$default"
}

# Env overrides take precedence (test seams + per-shell tuning).
WINDOW="${CLAUDE_CONTEXT_WINDOW:-$(setting autoCompactWindow 200000)}"
START_PCT="${CLAUDE_HANDOFF_START_PCT:-$(setting handoffReminderStartPct 60)}"
BAND_PCT="${CLAUDE_HANDOFF_BAND_PCT:-$(setting handoffReminderBandPct 10)}"

# Context size = the API's OWN usage report on the most recent assistant turn
# (input + cache_read + cache_creation tokens) — exact, and automatically
# correct after a /compact (the post-compact turn reports the shrunk context).
# Replaces the old 6-bytes/token transcript heuristic (observed error range
# 4.7–7.7 B/tok), which over/under-warned (June 2026 audit: 44% of context
# boundaries were still unmanaged compactions). Read from the transcript TAIL
# only (256KB) so this stays cheap on a Stop hook; fromjson? tolerates the
# truncated first line.
TOKENS=$(tail -c 262144 "$TRANSCRIPT" 2>/dev/null | jq -rRs '
  [split("\n")[] | fromjson? | .message.usage? | select(. != null)
   | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))]
  | last // 0' 2>/dev/null)
case "$TOKENS" in ''|*[!0-9]*) exit 0 ;; esac
[ "$TOKENS" -gt 0 ] || exit 0

PCT=$((TOKENS * 100 / WINDOW))

# Band-based dedup: once we cross START_PCT, only re-warn each time the
# percentage climbs into a new BAND_PCT-wide band. Keeps Stop hooks quiet
# between bands instead of firing every turn after the first crossing.
if [ "$PCT" -lt "$START_PCT" ]; then
    exit 0
fi

BAND=$(( (PCT - START_PCT) / BAND_PCT ))

STATE_DIR="${CLAUDE_HANDOFF_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
# Identify session for state — prefer session_id, fall back to transcript path hash.
STATE_KEY="${SESSION_ID:-$(printf '%s' "$TRANSCRIPT" | shasum 2>/dev/null | cut -c1-12)}"
STATE_FILE="$STATE_DIR/handoff-band-${STATE_KEY}"

# --- Context-gated memory-capture auto-trigger (once per session) -----------
# Before the compaction boundary, if this session accumulated high-signal
# markers, DIRECT Claude to run the interactive capture flow exactly once.
# Gated on its OWN marker (separate from the handoff band state) so it fires
# once and never every turn; gated on signal-markers existing so quiet/trivial
# sessions are never interrupted (this also keeps the handoff test green —
# those cases have no signal file).
CAP_STORE="${MEMORY_STORE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory}"
CAP_SIGNALS="$CAP_STORE/_pending/signals/${SESSION_ID}.jsonl"
CAP_MARK="$STATE_DIR/capture-triggered-${STATE_KEY}"
# Marker-write is a PRECONDITION of blocking: if the state dir is unwritable,
# the `( : > … )` fails, the && short-circuits, and we fall through to the
# normal handoff path — never blocking without the once-guard in place (a
# repeating block would otherwise fire every turn on a broken filesystem).
if [ ! -f "$CAP_MARK" ] && [ -s "$CAP_SIGNALS" ] && ( : > "$CAP_MARK" ) 2>/dev/null; then
    CAP_REASON="Context at ${PCT}% — run your once-per-session memory capture NOW, before the compaction boundary. Invoke the memory-capture skill (interactive path): distill this session's high-signal turns (markers in $CAP_SIGNALS) into candidate lessons, dedup each via hooks/lib/memory-dedup.sh, then AskUserQuestion keep/edit/drop and write ONLY accepted entries to .claude/memory/. Nothing is banked without an explicit accept. This auto-capture fires once per session."
    jq -n --arg r "$CAP_REASON" '{decision:"block", reason:$r}'
    exit 0
fi
# ---------------------------------------------------------------------------

LAST_BAND=-1
[ -f "$STATE_FILE" ] && LAST_BAND=$(cat "$STATE_FILE" 2>/dev/null) && [ -z "$LAST_BAND" ] && LAST_BAND=-1

if [ "$BAND" -gt "$LAST_BAND" ]; then
    printf '%s' "$BAND" > "$STATE_FILE" 2>/dev/null
    if [ "$PCT" -ge 70 ]; then
        MSG="Context at ${PCT}% (${TOKENS}/${WINDOW} tok, exact from API usage) — invoke handoff NOW, before auto-compaction takes the boundary."
    else
        MSG="Context at ${PCT}% (${TOKENS}/${WINDOW} tok, exact from API usage). Good moment to run /handoff at the next natural boundary, ahead of auto-compaction."
    fi
    # A project with a GitHub remote keeps its roadmap in GitHub Issues; remind
    # to update it alongside the handoff. The handoff prompt is throwaway, the
    # issue updates are the keeper. (rules/solo-project-roadmap.md)
    if git -C "$CWD" remote get-url origin >/dev/null 2>&1; then
        MSG="$MSG Also update your GitHub issues (close done, promote next→now, re-note blockers) before you wrap."
    fi
    jq -n --arg msg "$MSG" '{ systemMessage: $msg }'
fi

exit 0
