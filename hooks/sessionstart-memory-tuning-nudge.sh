#!/bin/sh
# sessionstart-memory-tuning-nudge.sh — SessionStart hook: says nothing until a
# deferred memory-tuning decision has finally accumulated enough evidence to
# make, then says it once.
#
# WHY THIS EXISTS: two facts about recall can only come from elapsed real usage
# — a probe you write proves a mechanism works and can never show it is USED. So
# the ERRORS-crowding decision was deliberately deferred to organic traffic. The
# gap that left is human: someone has to remember to go look. Asked twice in one
# session how not to forget, which is the signal that it should be mechanical.
#
# SILENT BY DEFAULT, AND THAT IS THE POINT. It fires only when the sample is
# large enough that a decision is actually available. A nudge that appears
# before you can act on it teaches you to ignore nudges, and then it is worse
# than nothing — the same reason doctor's permanently-yellow health check had
# stopped meaning anything.
#
# The baseline: everything at or before RECALL_MARK is this setup's own eval and
# probe traffic and must not be counted. Recorded 2026-09-01; see
# docs/audits/2026-09-01-memory-system-overhaul.md.
#
# Silence it:  touch "$XDG_STATE_HOME/claude-setup/memory-tuning-nudge.off"
# Seams (tests): RECALL_LOG_PATH, XDG_STATE_HOME, MEMTUNE_MIN_N, MEMTUNE_MIN_SHARE,
#                MEMTUNE_NUDGE_FORCE=1 (skip the once-ever throttle).
set +e

command -v jq >/dev/null 2>&1 || exit 0

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-setup"
[ -f "$STATE/memory-tuning-nudge.off" ] && exit 0

LOG="${RECALL_LOG_PATH:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory/_usage/recall-log.jsonl}"
[ -f "$LOG" ] || exit 0

RECALL_MARK=519
MIN_N="${MEMTUNE_MIN_N:-100}"
MIN_SHARE="${MEMTUNE_MIN_SHARE:-30}"

# Organic slice only: everything past the baseline line.
ORGANIC=$(tail -n +$((RECALL_MARK + 1)) "$LOG" 2>/dev/null)
[ -n "$ORGANIC" ] || exit 0

N=$(printf '%s\n' "$ORGANIC" | wc -l | tr -d ' ')
[ "${N:-0}" -ge "$MIN_N" ] || exit 0

# ERRORS' share of injected SLOTS, not of recalls — one recall can spend several
# slots on ERRORS entries, which is the crowding being measured.
SHARE=$(printf '%s\n' "$ORGANIC" | jq -r '.ids[]?' 2>/dev/null \
  | awk '{t++; if ($0 == "ERRORS") e++} END {if (t) printf "%d", 100*e/t; else printf "0"}')
[ "${SHARE:-0}" -ge "$MIN_SHARE" ] || exit 0

# Once ever. This is "the evidence is in, go decide", not a recurring reminder —
# and once you have decided, re-raising it is just noise.
mkdir -p "$STATE" 2>/dev/null
STAMP="$STATE/memory-tuning-nudged"
if [ "${MEMTUNE_NUDGE_FORCE:-0}" != "1" ] && [ -f "$STAMP" ]; then
  exit 0
fi
: > "$STAMP" 2>/dev/null

MSG="Memory tuning: ERRORS has held ${SHARE}% of injected recall slots across ${N} organic recalls — past the ${MIN_N}-recall bar set when this was deferred. ERRORS.md is ~56% of the index by chunk count, so it wins a slot on almost any query. The fix is a per-file slot cap in hooks/lib/memory-recall.py; \`claude-setup-doctor\` group 10 shows the current numbers."
jq -n --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
