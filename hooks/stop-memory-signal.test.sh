#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP/store"

# stub transcript: a correction from the user, a resolution from the assistant
T="$TMP/transcript.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"no, actually I meant the staging dir"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"Good catch — fixed it, all tests pass now."}}'
} > "$T"

printf '{"session_id":"sigtest","transcript_path":"%s"}' "$T" \
  | sh "$DIR/stop-memory-signal.sh"

SIG="$TMP/store/_pending/signals/sigtest.jsonl"
[ -f "$SIG" ] || { echo "FAIL: signal file not written"; exit 1; }
grep -q '"kind":"correction"' "$SIG" || { echo "FAIL: correction marker missing"; exit 1; }
grep -q '"kind":"resolved"'   "$SIG" || { echo "FAIL: resolved marker missing"; exit 1; }

# a boring exchange writes nothing
T2="$TMP/boring.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"what time is it"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"I cannot tell the time."}}'
} > "$T2"
printf '{"session_id":"boring","transcript_path":"%s"}' "$T2" \
  | sh "$DIR/stop-memory-signal.sh"
[ ! -f "$TMP/store/_pending/signals/boring.jsonl" ] \
  || { echo "FAIL: boring exchange should write no markers"; exit 1; }

# missing transcript path must not error (exit 0, no crash)
printf '{"session_id":"nofile","transcript_path":"/nope/missing.jsonl"}' \
  | sh "$DIR/stop-memory-signal.sh" || { echo "FAIL: missing transcript should exit 0"; exit 1; }

# empty session_id must not write anything and must exit 0
printf '{"session_id":"","transcript_path":"%s"}' "$T" \
  | sh "$DIR/stop-memory-signal.sh" || { echo "FAIL: empty session_id should exit 0"; exit 1; }
[ ! -f "$TMP/store/_pending/signals/.jsonl" ] \
  || { echo "FAIL: empty session_id should write nothing"; exit 1; }

# routine prose with bare word "fixed" must NOT produce a resolved marker
T3="$TMP/prose.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"can you update the config"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"I have fixed the indentation and updated the config file as requested."}}'
} > "$T3"
printf '{"session_id":"prose","transcript_path":"%s"}' "$T3" \
  | sh "$DIR/stop-memory-signal.sh"
[ ! -f "$TMP/store/_pending/signals/prose.jsonl" ] \
  || { echo "FAIL: routine prose with bare 'fixed' should NOT produce a resolved marker"; exit 1; }

echo "PASS"
