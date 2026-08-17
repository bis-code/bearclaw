#!/bin/sh
# memory-dedup.sh <index-name> <candidate-text>
# Searches the leann index for the candidate; prints "<max-jaccard> SKIP|NEW".
# SKIP when the best text-overlap match is a near-duplicate (>= MEMORY_DEDUP_THRESHOLD,
# 0.6 default Jaccard). Raw leann scores are UNNORMALIZED dot-products and not
# threshold-stable across text lengths — Jaccard on word tokens is scale-invariant.
# Test seam: MEMORY_SEARCH_CMD stubs the real leann call (offline tests).
set +e
NAME="$1"; CAND="$2"
THRESH="${MEMORY_DEDUP_THRESHOLD:-0.6}"

search() {
  if [ -n "${MEMORY_SEARCH_CMD+x}" ]; then eval "$MEMORY_SEARCH_CMD"; return; fi
  leann search "$NAME" "$CAND" --top-k 5 --json --non-interactive --show-metadata 2>/dev/null
}

JSON=$(search)
RC=$?
if [ "$RC" -ne 0 ] || [ -z "$JSON" ]; then
  # Search could not run (leann missing or failing): SAY so instead of coercing
  # to NEW — a dead index otherwise guarantees duplicate leakage while looking
  # healthy (banked: dedup-new-verdict-is-index-aged). Consumers treat
  # UNVERIFIED as "grep the memory dir manually before deciding".
  echo "memory-dedup: search unavailable (rc=$RC) — verdict UNVERIFIED" >&2
  printf '0.0 NEW UNVERIFIED\n'
  exit 0
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
