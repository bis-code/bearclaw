#!/bin/sh
# hooks/lib/memory-backend.sh — pluggable memory-backend dispatcher (SOURCED,
# not executed — it defines functions in the caller's shell).
#
# Default backend is "none" (plain file reads — no setup required). One
# opt-in backend is wired: local-embed, a small fastembed index over
# memory-global/*.md (install a local embedding model, set memoryBackend to
# "local-embed"). This file is the seam: a caller sources it, then calls one
# of the functions below instead of talking to any specific backend
# directly — with no backend configured, callers fall back to plain grep or
# eager file reads.
#
# Functions:
#   membackend_name
#     Prints the configured backend name on stdout: "$MEMORY_BACKEND" env if
#     set, else settings.json key "memoryBackend", else "none". Always
#     returns 0 — this is a name lookup, not a backend call.
#
#   membackend_search <corpus-name> <query> <top-k>
#   membackend_dedup  <corpus-name> <candidate-file>
#   membackend_health
#     Dispatch to the resolved backend. Exit-code contract (checked via $?
#     after calling — these are shell functions, not subprocesses, so they
#     `return`, never `exit`, and must not kill the sourcing script):
#       0 = results on stdout, one JSON object per line:
#           {"score":float,"path":str,"snippet":str}
#       3 = no backend / backend unavailable — caller falls back to grep or
#           eager load
#       1 = backend errored — caller treats this the same as 3 but may
#           surface a notice
#
# Settings file: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json (the LIVE
# settings the harness reads — install.sh copies the repo's settings.json
# there; it is not symlinked, so this must read the installed copy, not the
# repo file).
#
# Colocation contract: membackend-<name>.sh must live next to this file, in
# hooks/lib/. It is located via dirname of the SOURCING script's $0 — POSIX
# `.` does not update $0, so this only resolves correctly when the sourcing
# script itself lives in hooks/lib/ (true for every caller wired so far).
# MEMBACKEND_LIB_DIR overrides this (test seam / future callers elsewhere).

membackend_name() {
  if [ -n "${MEMORY_BACKEND:-}" ]; then
    printf '%s\n' "$MEMORY_BACKEND"
    return 0
  fi
  _mb_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if [ -f "$_mb_settings" ]; then
    _mb_val=$(jq -r '.memoryBackend // empty' "$_mb_settings" 2>/dev/null)
    if [ -n "$_mb_val" ] && [ "$_mb_val" != "null" ]; then
      printf '%s\n' "$_mb_val"
      return 0
    fi
  fi
  printf 'none\n'
  return 0
}

_membackend_lib_dir() {
  printf '%s\n' "${MEMBACKEND_LIB_DIR:-$(CDPATH= cd "$(dirname "$0")" && pwd)}"
}

# $1 = op (search|dedup), remaining args forwarded verbatim.
_membackend_dispatch() {
  _mb_op="$1"; shift
  _mb_backend=$(membackend_name)
  case "$_mb_backend" in
    none)
      return 3
      ;;
    local-embed)
      _mb_script="$(_membackend_lib_dir)/membackend-$_mb_backend.sh"
      if [ -x "$_mb_script" ]; then
        "$_mb_script" "$_mb_op" "$@"
        return $?
      fi
      return 3
      ;;
    *)
      printf 'memory-backend: unknown backend "%s" — falling back\n' "$_mb_backend" >&2
      return 3
      ;;
  esac
}

membackend_search() {
  _membackend_dispatch search "$@"
}

membackend_dedup() {
  _membackend_dispatch dedup "$@"
}

# 0 = backend is actually serving (venv/deps/index present); 3 = not serving
# (including "none"). Callers use this to gate slim mode on HEALTH, not just
# on a configured NAME — a named-but-dead backend must fall back to eager
# load, not silently serve nothing.
membackend_health() {
  _membackend_dispatch health "$@"
}
