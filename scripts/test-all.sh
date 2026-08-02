#!/usr/bin/env bash
# Aggregate test runner. Exit 0 iff every suite passes. Used by CI and pre-push.
set -uo pipefail

REPO="$(CDPATH= cd -P "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$REPO"

pass=0; fail=0; failed=()

OUT="$(mktemp "${TMPDIR:-/tmp}/claude-test-out.XXXXXX")"
trap 'rm -f "$OUT"' EXIT

run() { # <label> <command...>
  local label="$1"; shift
  if "$@" >"$OUT" 2>&1; then
    pass=$((pass+1)); printf '  ok   %s\n' "$label"
  else
    fail=$((fail+1)); failed+=("$label")
    printf '  FAIL %s\n' "$label"; sed 's/^/       /' "$OUT" | head -20
  fi
}

echo "shell suites:"
for t in hooks/*.test.sh hooks/lib/*.test.sh bin/*.test.sh; do
  [ -f "$t" ] || continue
  run "$t" sh "$t"
done

echo "python suites:"
for t in hooks/lib/*.test.py; do
  [ -f "$t" ] || continue
  run "$t" python3 "$t"
done

echo "bats suites:"
if command -v bats >/dev/null 2>&1; then
  for t in scripts/tests/*.bats; do
    [ -f "$t" ] || continue
    run "$t" bats "$t"
  done
else
  echo "  skip (bats not installed)"
fi

echo "identity gate:"
run "no identity leaks" ./scripts/check-no-identity.sh

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
  printf 'failed suites:\n'; printf '  %s\n' "${failed[@]}"
  exit 1
fi
exit 0
