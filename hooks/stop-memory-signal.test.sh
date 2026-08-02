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

# --- regressions found by draining the capture queue, 2026-08-02 -------------
# All three were observed live: 5 of 5 markers in a 22-session queue were false
# positives, and none of the recorded snippets contained the text that fired.

# A long paste with a stray trigger word deep inside is not a reaction.
# Observed: "Nice" at ~char 9000 of a 15KB pasted prompt emitted `praise`, four
# times across four sessions, and the head-200 snippet never showed why.
T4="$TMP/paste.jsonl"
PASTE="You are a retention editor. $(awk 'BEGIN{while(i++<300)printf "filler words here "}')Nice work is expected."
{
  printf '{"message":{"role":"user","content":%s}}\n' "$(printf '%s' "$PASTE" | jq -Rs .)"
  printf '%s\n' '{"message":{"role":"assistant","content":"Understood."}}'
} > "$T4"
printf '{"session_id":"paste","transcript_path":"%s"}' "$T4" \
  | sh "$DIR/stop-memory-signal.sh"
[ ! -f "$TMP/store/_pending/signals/paste.jsonl" ] \
  || { echo "FAIL: stray trigger deep in a long paste must not emit a marker"; exit 1; }

# Tool results are recorded with role=="user". They are the harness talking, not
# the human. Observed: CLI stderr "Incorrect store password" emitted `correction`.
T5="$TMP/toolresult.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"run the deploy"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"Running it."}}'
  printf '%s\n' '{"toolUseResult":{"stdout":"x"},"message":{"role":"user","content":"Error: incorrect store password"}}'
} > "$T5"
printf '{"session_id":"toolresult","transcript_path":"%s"}' "$T5" \
  | sh "$DIR/stop-memory-signal.sh"
[ ! -f "$TMP/store/_pending/signals/toolresult.jsonl" ] \
  || { echo "FAIL: a tool result must not be read as a user turn"; exit 1; }

# Injected <system-reminder> blocks are harness text appended to the user turn.
# A trigger inside one is not the user correcting anything.
T6="$TMP/reminder.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"update the readme\n<system-reminder>\nrecalled memory: no, actually the path moved\n</system-reminder>"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"Done."}}'
} > "$T6"
printf '{"session_id":"reminder","transcript_path":"%s"}' "$T6" \
  | sh "$DIR/stop-memory-signal.sh"
[ ! -f "$TMP/store/_pending/signals/reminder.jsonl" ] \
  || { echo "FAIL: a trigger inside <system-reminder> must not emit a marker"; exit 1; }

# A marker must be auditable: the snippet has to contain the text that fired it.
# The assistant's "all tests pass" lands at the END of a long turn, well past the
# head that used to be recorded — so the old snippet proved nothing.
T7="$TMP/snippet.jsonl"
LONG_ASST="Here is what I changed. $(awk 'BEGIN{while(i++<40)printf "I touched another file and explained it at length. "}')Reran the suite. All tests pass."
{
  printf '%s\n' '{"message":{"role":"user","content":"no, actually I meant the staging dir"}}'
  printf '{"message":{"role":"assistant","content":%s}}\n' "$(printf '%s' "$LONG_ASST" | jq -Rs .)"
} > "$T7"
printf '{"session_id":"snippet","transcript_path":"%s"}' "$T7" \
  | sh "$DIR/stop-memory-signal.sh"
SNIP="$TMP/store/_pending/signals/snippet.jsonl"
jq -e 'select(.kind=="correction") | .snippet | test("no, actually"; "i")' "$SNIP" >/dev/null \
  || { echo "FAIL: correction snippet must contain the matched text"; exit 1; }
jq -e 'select(.kind=="resolved") | .snippet | test("all tests pass"; "i")' "$SNIP" >/dev/null \
  || { echo "FAIL: resolved snippet must contain the matched text"; exit 1; }

# True positives must survive the tightening. Precision is worthless if the
# detector now fires on nothing — an earlier attempt used "\b" as a word
# boundary, which `awk -v` turned into a literal backspace, silently killing
# every praise marker while the false-positive tests all still passed.
T8="$TMP/genuine.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"perfect, now wire it into the runner"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"Wired."}}'
} > "$T8"
printf '{"session_id":"genuine","transcript_path":"%s"}' "$T8" \
  | sh "$DIR/stop-memory-signal.sh"
jq -e 'select(.kind=="praise") | .snippet | test("perfect"; "i")' \
  "$TMP/store/_pending/signals/genuine.jsonl" >/dev/null 2>&1 \
  || { echo "FAIL: a genuine leading reaction must still emit praise"; exit 1; }

# ...but the trigger must be a whole word, not a prefix.
T9="$TMP/prefix.jsonl"
{
  printf '%s\n' '{"message":{"role":"user","content":"nicely done is not the same as a reaction"}}'
  printf '%s\n' '{"message":{"role":"assistant","content":"Noted."}}'
} > "$T9"
printf '{"session_id":"prefix","transcript_path":"%s"}' "$T9" \
  | sh "$DIR/stop-memory-signal.sh"
[ ! -f "$TMP/store/_pending/signals/prefix.jsonl" ] \
  || { echo "FAIL: 'nicely' must not match the 'nice' trigger"; exit 1; }

echo "PASS"
