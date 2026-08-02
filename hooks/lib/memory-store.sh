#!/bin/sh
# memory-store.sh — staging-store primitives for Phase-2 memory capture.
# SOURCE this file (`. memory-store.sh`); do not execute it. Defines the on-disk
# layout of the machine-local capture + usage store and the helpers to touch it.
#
# Layout (under MEMSTORE_BASE):
#   _pending/raw/      raw-capture pointer JSONs awaiting Claude-active distill
#   _pending/signals/  per-session high-signal markers (<session>.jsonl)
#   _pending/done/     raw captures already drained (audit trail, age-bounded)
#   _usage/            recall-log.jsonl and friends (scoring inputs)

MEMSTORE_BASE="${MEMORY_STORE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory}"
_MEMSTORE_PENDING="$MEMSTORE_BASE/_pending"
MEMSTORE_RAW="$_MEMSTORE_PENDING/raw"
MEMSTORE_SIGNALS="$_MEMSTORE_PENDING/signals"
MEMSTORE_DONE="$_MEMSTORE_PENDING/done"
MEMSTORE_USAGE="$MEMSTORE_BASE/_usage"

memstore_init() {
  mkdir -p "$MEMSTORE_RAW" "$MEMSTORE_SIGNALS" "$MEMSTORE_DONE" "$MEMSTORE_USAGE" 2>/dev/null || return 0
}

# memstore_enqueue_raw <json-string> -> echoes the written path
memstore_enqueue_raw() {
  memstore_init
  # Note: macOS mktemp does not substitute X's when a non-X suffix follows them
  # (e.g. XXXXXX.json), so we create the temp file without a suffix and then
  # append .json.  The mv is atomic on the same filesystem.
  _tmp=$(mktemp "$MEMSTORE_RAW/XXXXXX") || return 0
  _f="${_tmp}.json"
  mv "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp"; return 0; }
  unset _tmp
  printf '%s\n' "$1" > "$_f" 2>/dev/null || { rm -f "$_f"; return 0; }
  printf '%s\n' "$_f"
}

# memstore_list_raw -> one pending raw path per line (none -> nothing)
memstore_list_raw() {
  [ -d "$MEMSTORE_RAW" ] || return 0
  for _f in "$MEMSTORE_RAW"/*.json; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
}

# memstore_mark_done <raw-path>
memstore_mark_done() {
  [ -f "$1" ] || return 0
  memstore_init
  mv "$1" "$MEMSTORE_DONE/" 2>/dev/null || return 0
}

# memstore_prune_done [days] — bound the audit trail (default MEMSTORE_KEEP_DAYS
# or 30). Deletes drained pointers and spent signal files older than <days>.
#
# 30 rather than a longer window because a pointer is only as useful as the
# transcript it points at: of the 490 drained pointers measured on 2026-08-02,
# 256 of the 263 older than 30 days referenced transcripts that no longer
# existed. Checking liveness per file would mean a jq call per pointer inside a
# SessionEnd hook, so age is the cheap proxy for the same thing.
#
# Only the audit trail is touched. Pending captures in raw/ are NEVER pruned by
# age: an undrained pointer is unfinished work, not history, and a queue the
# user has not gotten to yet must not evaporate for being old.
#
# Uses find -mtime rather than stat: `stat -f` is BSD-only and `-f` means
# --file-system on GNU, which is exactly the portability trap that has bitten
# this repo before. -mtime is POSIX on both.
memstore_prune_done() {
  _days="${1:-${MEMSTORE_KEEP_DAYS:-30}}"
  case "$_days" in ''|*[!0-9]*) return 0 ;; esac
  [ "$_days" -gt 0 ] 2>/dev/null || return 0
  [ -d "$MEMSTORE_DONE" ] && \
    find "$MEMSTORE_DONE" -type f -name '*.json' -mtime +"$_days" -exec rm -f {} + 2>/dev/null
  [ -d "$MEMSTORE_SIGNALS" ] && \
    find "$MEMSTORE_SIGNALS" -type f -name '*.jsonl' -mtime +"$_days" -exec rm -f {} + 2>/dev/null
  return 0
}

# memstore_append_signal <session-id> <json-string>
memstore_append_signal() {
  memstore_init
  printf '%s\n' "$2" >> "$MEMSTORE_SIGNALS/$1.jsonl" 2>/dev/null || return 0
}

# memstore_append_usage <jsonl-name> <json-string>
memstore_append_usage() {
  memstore_init
  printf '%s\n' "$2" >> "$MEMSTORE_USAGE/$1" 2>/dev/null || return 0
}
