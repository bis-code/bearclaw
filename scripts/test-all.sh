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

# ---- always-loaded size guard (S4 rules diet, 2026-08-16) -------------------
# Ceilings are ADJUSTABLE constants: raising one is a conscious, visible-in-
# diff decision (trim elsewhere or bump deliberately) — never silent accretion.
# Chars measured AFTER stripping <!-- --> comments (stripped from loaded
# context by the harness, so they're free).
CLAUDE_MD_MAX=6000
RULES_MAX=17000   # raised 16000->17000 2026-08-16: reserved headroom for the approved wave-6 rules (two-machine-sync, op-run convention)
strip_comments() { perl -0pe 's/<!--.*?-->//gs' "$1"; }
CM=$(strip_comments CLAUDE.md | wc -c)
RT=0
for f in rules/*.md; do
  case "$f" in rules/about-me.local.md) continue ;; esac
  RT=$((RT + $(strip_comments "$f" | wc -c)))
done
echo "size guard: CLAUDE.md=${CM}/${CLAUDE_MD_MAX} rules/=${RT}/${RULES_MAX} (comment-stripped chars)"
if [ "$CM" -gt "$CLAUDE_MD_MAX" ] || [ "$RT" -gt "$RULES_MAX" ]; then
  echo "  FAIL size guard: always-loaded set over ceiling — run the rules-diet (trim or consciously raise the constant in scripts/test-all.sh)"
  fail=$((fail+1)); failed+=("size-guard (always-loaded ceiling)")
else
  pass=$((pass+1))
fi


echo
printf '%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
  printf 'failed suites:\n'; printf '  %s\n' "${failed[@]}"
  exit 1
fi
exit 0

