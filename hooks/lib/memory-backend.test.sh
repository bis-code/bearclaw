#!/bin/sh
# Tests for memory-backend.sh — the pluggable memory-backend dispatcher.
# NO set -e: every case captures an intentional exit code (0/1/3) from a
# sourced shell function, and a bare failing statement would trip errexit.
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0

check() {
  label="$1"; out="$2"; expect="$3"
  if printf '%s' "$out" | grep -q "$expect"; then
    echo "PASS: $label"
    PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected $expect, got: $out"
    FAIL=$((FAIL+1))
  fi
}

checkrc() {
  label="$1"; rc="$2"; expect="$3"
  if [ "$rc" -eq "$expect" ]; then
    echo "PASS: $label"
    PASS=$((PASS+1))
  else
    echo "FAIL: $label — expected rc=$expect, got rc=$rc"
    FAIL=$((FAIL+1))
  fi
}

. "$DIR/memory-backend.sh"

TMP=$(mktemp -d)

# ---- membackend_name resolution order: env > settings.json > none ----

mkdir -p "$TMP/with-settings"
printf '{"memoryBackend": "local-embed"}\n' > "$TMP/with-settings/settings.json"

out=$(CLAUDE_CONFIG_DIR="$TMP/with-settings" MEMORY_BACKEND=none membackend_name)
check "env wins over settings.json" "$out" "^none$"

out=$(CLAUDE_CONFIG_DIR="$TMP/with-settings" membackend_name)
check "settings.json wins over default" "$out" "^local-embed$"

mkdir -p "$TMP/no-settings"
out=$(CLAUDE_CONFIG_DIR="$TMP/no-settings" membackend_name)
check "no env, no settings.json -> none" "$out" "^none$"

# ---- search/dedup exit 3 under "none" ----

export MEMORY_BACKEND=none
membackend_search some-corpus "a query" 5 >/dev/null 2>&1; rc=$?
checkrc "membackend_search exit 3 under none" "$rc" 3

membackend_dedup some-corpus "$TMP/cand.md" >/dev/null 2>&1; rc=$?
checkrc "membackend_dedup exit 3 under none" "$rc" 3
unset MEMORY_BACKEND

# ---- unknown backend: one stderr line + exit 3 ----

export MEMORY_BACKEND=some-bogus-backend
err=$(membackend_search some-corpus "a query" 5 2>&1 1>/dev/null); rc=$?
checkrc "unknown backend -> exit 3" "$rc" 3
check "unknown backend -> stderr notice" "$err" "unknown backend"
unset MEMORY_BACKEND

# ---- dispatch actually reaches membackend-local-embed.sh when
# backend=local-embed, using a bogus venv so the assertion is hermetic
# regardless of whether fastembed happens to be installed here.

export MEMORY_BACKEND=local-embed
export MEMORY_VENV="$TMP/no-such-venv"
err=$(membackend_search some-corpus "a query" 5 2>&1 1>/dev/null); rc=$?
checkrc "dispatch to local-embed -> exit 3 (no venv)" "$rc" 3
check "dispatch to local-embed -> venv-missing message surfaces" "$err" "venv python not found"

err=$(membackend_dedup some-corpus "$TMP/cand.md" 2>&1 1>/dev/null); rc=$?
checkrc "dedup dispatch to local-embed -> exit 3 (no venv)" "$rc" 3
unset MEMORY_BACKEND MEMORY_VENV

rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
