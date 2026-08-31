#!/bin/sh
# memory-dedup.sh <index-name> <candidate-text>
# Searches the configured memory backend for the candidate; prints
# "<max-jaccard> SKIP|NEW". SKIP when the best text-overlap match is a
# near-duplicate (>= MEMORY_DEDUP_THRESHOLD, 0.6 default Jaccard). Backend
# scores (e.g. leann's, historically) can be unnormalized and not
# threshold-stable across text lengths — Jaccard on word tokens is
# scale-invariant, so the raw score is never thresholded directly.
# Test seam: MEMORY_SEARCH_CMD stubs the search() fallback below (offline
# tests) — leann itself has been retired (T15); search() is now that seam
# only, with no real backend behind it.
#
# Backend adapter (hooks/lib/memory-backend.sh) is tried FIRST via
# membackend_dedup. On exit 0 its JSONL hits ({"score","path","snippet"}) are
# reshaped into the {"text":...} array the Jaccard step below already expects,
# so no computation is duplicated. On exit 3 (no backend / unavailable) this
# falls through to search() below, which has nothing left to try in
# production and reports UNVERIFIED (see below) unless a test stubs it.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$DIR/memory-backend.sh"

NAME="$1"; CAND="$2"
THRESH="${MEMORY_DEDUP_THRESHOLD:-0.6}"

search() {
  if [ -n "${MEMORY_SEARCH_CMD+x}" ]; then eval "$MEMORY_SEARCH_CMD"; return; fi
  return 1
}

JSON=""
CAND_FILE=$(mktemp 2>/dev/null) || CAND_FILE=""
if [ -n "$CAND_FILE" ]; then
  printf '%s' "$CAND" > "$CAND_FILE"
  ADAPTER_OUT=$(membackend_dedup "$NAME" "$CAND_FILE")
  ADAPTER_RC=$?
  rm -f "$CAND_FILE"
else
  ADAPTER_RC=3
fi

if [ "$ADAPTER_RC" -eq 0 ]; then
  JSON=$(printf '%s\n' "$ADAPTER_OUT" | jq -s '[.[] | {text: .snippet}]' 2>/dev/null)
  JQ_RC=$?
  if [ "$JQ_RC" -ne 0 ]; then
    # Adapter reported success (rc=0) but its output didn't parse — a
    # backend bug, not "zero matches". Do NOT let a parse failure
    # masquerade as an empty result (the same "confident wrong verdict"
    # hole this file already guards against below, one seam over).
    # Fall through to search() below exactly as ADAPTER_RC=3 would.
    JSON=""
    echo "memory-dedup: adapter reported success but output was unparseable — falling back" >&2
  fi
fi

if [ -z "$JSON" ]; then
  JSON=$(search)
  RC=$?
  if [ "$RC" -ne 0 ] || [ -z "$JSON" ]; then
    # Search could not run (no backend configured, or it's down): SAY so
    # instead of coercing to NEW — a dead index otherwise guarantees duplicate
    # leakage while looking healthy (banked: dedup-new-verdict-is-index-aged).
    # Consumers treat UNVERIFIED as "grep the memory dir manually before deciding".
    echo "memory-dedup: search unavailable (rc=$RC) — verdict UNVERIFIED" >&2
    printf '0.0 NEW UNVERIFIED\n'
    exit 0
  fi
fi

# Compute max Jaccard similarity between candidate and each hit's .text field.
# Guard: any parse/runtime error -> print "0.0" (fail-open -> NEW).
MAX_JAC=$(DEDUP_JSON="$JSON" python3 - "$CAND" <<'PYEOF'
import sys, os, json, re

def tokenize(s):
    return set(t for t in re.split(r'[^a-zA-Z0-9]+', s.lower()) if t)

cand_tokens = tokenize(sys.argv[1])
raw = os.environ.get("DEDUP_JSON", "")
try:
    hits = json.loads(raw)
    if not isinstance(hits, list) or not hits:
        print("0.0")
        sys.exit(0)
    max_j = 0.0
    for h in hits:
        text = h.get("text", "") if isinstance(h, dict) else ""
        if not text:
            continue
        ht = tokenize(str(text))
        union = cand_tokens | ht
        if not union:
            continue
        j = len(cand_tokens & ht) / len(union)
        if j > max_j:
            max_j = j
    print(round(max_j, 4))
except Exception:
    print("0.0")
PYEOF
)

case "$MAX_JAC" in ''|null) MAX_JAC=0.0 ;; esac

# float compare via awk (POSIX sh has no float test)
VERDICT=$(awk -v m="$MAX_JAC" -v t="$THRESH" 'BEGIN { print (m+0 >= t+0) ? "SKIP" : "NEW" }')
printf '%s %s\n' "$MAX_JAC" "$VERDICT"
exit 0
