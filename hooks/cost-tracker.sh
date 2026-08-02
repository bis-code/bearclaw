#!/bin/sh
# cost-tracker.sh — Stop hook (user scope, all projects).
#
# Appends ONE per-turn DELTA cost row to $METRICS_DIR/costs.jsonl after each
# assistant response. NON-BLOCKING: the transcript parse + write run in a
# detached background worker (all fds -> cost-tracker.log) so this hook adds
# ~0 latency to the turn. The Stop payload carries no usage, so the worker
# sums token usage from the session transcript JSONL (Claude Code's own file).
#
# Each row is the DELTA since the previous Stop for this session, tracked via a
# per-session cursor file. Delta rows make today/by-project/last-7d a plain
# SUM + date-filter (see bin/claude-cost-report).
#
# FAILURE OBSERVABILITY: a detached worker cannot talk back to the current turn,
# so on any write failure the worker drops a $METRICS_DIR/.cost-tracker.error
# marker; this hook's synchronous head surfaces it via systemMessage on the
# NEXT turn, then clears it. Persistent failures re-nag; transient ones show once.
#
# Always exits 0 — Stop completion must never be blocked by this hook.
#
# Test seams: CLAUDE_COST_TRACKER_SYNC=1 runs the worker in foreground;
# CLAUDE_METRICS_DIR overrides the metrics dir (default ~/.claude/metrics).

set +e

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

METRICS_DIR="${CLAUDE_METRICS_DIR:-$HOME/.claude/metrics}"
ERR_FILE="$METRICS_DIR/.cost-tracker.error"
LOG_FILE="$METRICS_DIR/cost-tracker.log"

# --- Synchronous head: surface any pending worker failure (fast: stat + read) ---
if [ -f "$ERR_FILE" ]; then
    LAST_ERR=$(cat "$ERR_FILE" 2>/dev/null)
    jq -n --arg m "cost-tracker: last write failed — ${LAST_ERR} (see $LOG_FILE)" '{ systemMessage: $m }'
    rm -f "$ERR_FILE" 2>/dev/null
fi

# Resolve transcript: prefer stdin, else find by session_id.
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    if [ -n "$SESSION_ID" ]; then
        TRANSCRIPT=$(find "$HOME/.claude/projects" -maxdepth 3 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
    fi
fi
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

record_error() {
    mkdir -p "$METRICS_DIR" 2>/dev/null
    _ts=$(date +%FT%T%z)
    printf '%s\t%s\n' "$_ts" "$1" >> "$LOG_FILE" 2>/dev/null
    printf '%s\t%s\n' "$_ts" "$1" >  "$ERR_FILE" 2>/dev/null
}

worker() {
    # Sum cumulative usage from the transcript. -sR + fromjson? tolerates
    # malformed/partial lines (one bad line must not zero the whole session).
    SUMS=$(jq -rRs '
        [ split("\n")[] | select(. != "") | (fromjson? // empty) ] as $all
        | ( [ $all[] | select(.type=="assistant") | .message.usage // empty ] ) as $u
        | ( [ $u[].input_tokens                // 0 ] | add // 0 ) as $i
        | ( [ $u[].output_tokens               // 0 ] | add // 0 ) as $o
        | ( [ $u[].cache_creation_input_tokens // 0 ] | add // 0 ) as $cw
        | ( [ $u[].cache_read_input_tokens     // 0 ] | add // 0 ) as $cr
        | ( [ $all[] | select(.type=="assistant") | .message.model // empty ]
              | map(select(. != "")) | last // "unknown" ) as $model
        | "\($i) \($o) \($cw) \($cr) \($model)"
    ' "$TRANSCRIPT" 2>/dev/null)
    [ -z "$SUMS" ] && return

    # shellcheck disable=SC2086
    set -- $SUMS
    CI=$1; CO=$2; CCW=$3; CCR=$4; MODEL=${5:-unknown}
    case "$CI$CO$CCW$CCR" in *[!0-9]*) return ;; esac

    CURSOR_DIR="$METRICS_DIR/cursors"
    CURSOR_FILE="$CURSOR_DIR/${SESSION_ID:-default}.cursor"
    PI=0; PO=0; PCW=0; PCR=0
    if [ -f "$CURSOR_FILE" ]; then
        read -r PI PO PCW PCR _ < "$CURSOR_FILE" 2>/dev/null
        case "$PI$PO$PCW$PCR" in *[!0-9]*) PI=0; PO=0; PCW=0; PCR=0 ;; esac
    fi

    # Deltas. Negative (transcript reset across --resume) -> fall back to cumulative.
    DI=$((CI - PI));    [ "$DI"  -lt 0 ] && DI=$CI
    DO=$((CO - PO));    [ "$DO"  -lt 0 ] && DO=$CO
    DCW=$((CCW - PCW)); [ "$DCW" -lt 0 ] && DCW=$CCW
    DCR=$((CCR - PCR)); [ "$DCR" -lt 0 ] && DCR=$CCR

    if [ "$DI" -eq 0 ] && [ "$DO" -eq 0 ] && [ "$DCW" -eq 0 ] && [ "$DCR" -eq 0 ]; then
        return
    fi

    # Project from cwd: git repo root basename, else cwd basename.
    PROJECT="unknown"
    if [ -n "$CWD" ]; then
        ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$ROOT" ]; then PROJECT=$(basename "$ROOT"); else PROJECT=$(basename "$CWD"); fi
    fi

    mkdir -p "$METRICS_DIR" 2>/dev/null || { record_error "mkdir $METRICS_DIR failed"; return; }

    # Build row with jq (safe JSON encoding + cost math in one pass). Rates are USD
    # per 1M tokens (cacheWrite=1.25x in, cacheRead~0.1x in); approximate and
    # editable — the report labels cost as "est". Computing cost in jq (not awk)
    # yields canonical numbers (jq 1.7+ preserves literal trailing zeros).
    # Local-time ts -> wall-clock daily split.
    TS=$(date +%FT%T%z)
    ROW=$(jq -nc \
        --arg ts "$TS" --arg sid "${SESSION_ID:-default}" --arg proj "$PROJECT" --arg model "$MODEL" \
        --argjson i "$DI" --argjson o "$DO" --argjson cw "$DCW" --argjson cr "$DCR" '
        ($model | ascii_downcase) as $m
        | (if   ($m | test("haiku")) then {i:0.80, o:4.0,  cw:1.00,  cr:0.08}
           elif ($m | test("opus"))  then {i:15.0, o:75.0, cw:18.75, cr:1.50}
           else                            {i:3.0,  o:15.0, cw:3.75,  cr:0.30} end) as $r
        | ((((($i/1e6)*$r.i + ($o/1e6)*$r.o + ($cw/1e6)*$r.cw + ($cr/1e6)*$r.cr) * 1e6 | round) / 1e6)) as $cost
        | {timestamp:$ts, session_id:$sid, project:$proj, model:$model,
           input_tokens:$i, output_tokens:$o, cache_write_tokens:$cw,
           cache_read_tokens:$cr, estimated_cost_usd:$cost}' 2>/dev/null)
    [ -z "$ROW" ] && { record_error "jq row build failed"; return; }

    # Atomic append (row < 512B). Guarded: any failure -> marker, never silent.
    if ! printf '%s\n' "$ROW" >> "$METRICS_DIR/costs.jsonl" 2>/dev/null; then
        record_error "append to costs.jsonl failed (disk full? perms? path is a dir?)"
        return
    fi

    # Success -> clear stale marker, advance cursor to current cumulative.
    rm -f "$ERR_FILE" 2>/dev/null
    mkdir -p "$CURSOR_DIR" 2>/dev/null
    printf '%s %s %s %s %s\n' "$CI" "$CO" "$CCW" "$CCR" "$MODEL" > "$CURSOR_FILE" 2>/dev/null
}

# Create the metrics dir in the PARENT before detaching: the worker's log
# redirect (>>"$LOG_FILE") can't open in a missing dir, which kills the worker
# before its own mkdir runs (chicken-and-egg → no data was ever written).
mkdir -p "$METRICS_DIR" 2>/dev/null

if [ -n "$CLAUDE_COST_TRACKER_SYNC" ]; then
    worker
else
    # Detach: redirect all fds away from the hook's pipes so Claude Code sees
    # EOF and unblocks immediately while the worker continues in the background.
    worker </dev/null >>"$LOG_FILE" 2>&1 &
fi

exit 0
