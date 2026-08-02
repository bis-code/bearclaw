#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"
T="$TMP/t.jsonl"; printf '{}\n' > "$T"

printf '{"session_id":"capX","transcript_path":"%s","cwd":"%s"}' "$T" "$TMP" \
  | sh "$DIR/sessionend-memory-capture.sh"

RAW="$TMP/store/_pending/raw"
n=$(ls "$RAW"/*.json 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "1" ] || { echo "FAIL: expected 1 raw capture, got $n"; exit 1; }
F=$(ls "$RAW"/*.json)
grep -q '"session"' "$F"          || { echo "FAIL: session key missing"; exit 1; }
grep -q '"transcript_path"' "$F"  || { echo "FAIL: transcript_path key missing"; exit 1; }
grep -q '"signal_file"' "$F"      || { echo "FAIL: signal_file key missing"; exit 1; }
grep -q "capX" "$F"               || { echo "FAIL: session id not recorded"; exit 1; }
echo "$F" | grep -q . && grep -q '"project"' "$F" || { echo "FAIL: project key missing"; exit 1; }

# empty stdin must not crash or write a malformed capture
printf '' | sh "$DIR/sessionend-memory-capture.sh" || { echo "FAIL: empty stdin should exit 0"; exit 1; }

# PreCompact event is recorded faithfully in the pointer
TMP2=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP2/store"
T2="$TMP2/t2.jsonl"; printf '{}\n' > "$T2"
printf '{"session_id":"compX","transcript_path":"%s","cwd":"%s","hook_event_name":"PreCompact"}' "$T2" "$TMP2" \
  | sh "$DIR/sessionend-memory-capture.sh"
RAW2="$TMP2/store/_pending/raw"
n2=$(ls "$RAW2"/*.json 2>/dev/null | wc -l | tr -d ' ')
[ "$n2" = "1" ] || { echo "FAIL: expected 1 raw capture for PreCompact, got $n2"; exit 1; }
F2=$(ls "$RAW2"/*.json)
grep -q '"event":"PreCompact"' "$F2" || { echo "FAIL: event field should be PreCompact"; exit 1; }

# Default (no hook_event_name) yields SessionEnd
TMP3=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP3/store"
T3="$TMP3/t3.jsonl"; printf '{}\n' > "$T3"
printf '{"session_id":"defX","transcript_path":"%s","cwd":"%s"}' "$T3" "$TMP3" \
  | sh "$DIR/sessionend-memory-capture.sh"
RAW3="$TMP3/store/_pending/raw"
F3=$(ls "$RAW3"/*.json)
grep -q '"event":"SessionEnd"' "$F3" || { echo "FAIL: default event field should be SessionEnd"; exit 1; }

echo "PASS"
