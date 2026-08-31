#!/bin/sh
# memory-store.sh — usage-log primitives for semantic recall scoring.
# SOURCE this file (`. memory-store.sh`); do not execute it. Defines the on-disk
# layout of the machine-local usage store and the helper to touch it.
#
# Layout (under MEMSTORE_BASE):
#   _usage/            recall-log.jsonl and friends (recency/frequency scoring
#                       inputs for userpromptsubmit-memory-recall.sh + memory-prune.sh)
#
# T9 (2026-08-30): the _pending/{raw,signals,done} capture-queue tier and its
# helpers (memstore_enqueue_raw, memstore_list_raw, memstore_mark_done,
# memstore_prune_done, memstore_append_signal) were removed along with the
# review-queue machinery (sessionend-memory-capture.sh, stop-memory-signal.sh,
# skills/memory-capture/) — the 1700+-item human-review queue was the reason
# it accumulated, and Cognee (via hooks/lib/memory-backend.sh) replaces the
# need for a Claude-active distill step. This file now only backs the usage
# log, which stays live (userpromptsubmit-memory-recall.sh, memory-prune.sh).

MEMSTORE_BASE="${MEMORY_STORE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory}"
MEMSTORE_USAGE="$MEMSTORE_BASE/_usage"

memstore_init() {
  mkdir -p "$MEMSTORE_USAGE" 2>/dev/null || return 0
}

# memstore_append_usage <jsonl-name> <json-string>
memstore_append_usage() {
  memstore_init
  printf '%s\n' "$2" >> "$MEMSTORE_USAGE/$1" 2>/dev/null || return 0
}
