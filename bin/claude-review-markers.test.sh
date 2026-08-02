#!/bin/sh
# Tests for claude-review-markers: discovers REVIEW(claude): markers in the
# git-tracked tree as a JSON worklist. Builds a throwaway git repo as fixture.
BIN="$(cd "$(dirname "$0")" && pwd)/claude-review-markers"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0; ok(){ echo "ok   $1"; }; bad(){ echo "FAIL $1 ($2)"; fail=1; }

# Non-git dir -> [] (skill falls back to PR mode)
out=$(cd "$TMP" && sh "$BIN")
[ "$out" = "[]" ] && ok "non-git -> []" || bad "non-git" "$out"

# Fixture git repo with markers across comment styles + a gitignored file
R="$TMP/repo"; mkdir -p "$R"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t )
printf 'func x() {\n  // REVIEW(claude): handle the empty slice\n}\n' > "$R/a.go"
printf '/// REVIEW(claude): rename this symbol\nlet y = 1\n' > "$R/b.swift"
printf '# REVIEW(claude): add a docstring\ndef z(): pass\n' > "$R/c.py"
printf '<!-- REVIEW(claude): fix alt text -->\n<img>\n' > "$R/d.html"
printf 'no marker here\n' > "$R/clean.txt"
printf 'Docs mention the `REVIEW(claude):` tag in prose — must NOT match.\n' > "$R/notes.md"
printf '*.ignored\n' > "$R/.gitignore"
printf '// REVIEW(claude): should NOT appear (gitignored)\n' > "$R/skip.ignored"
( cd "$R" && git add -A && git commit -qm init )

WL=$(cd "$R" && sh "$BIN")
[ "$(printf '%s' "$WL" | jq 'length')" = "4" ] && ok "finds 4 markers (prose mention excluded)" || bad "count" "$WL"
printf '%s' "$WL" | jq -e 'any(.[]; .file=="notes.md") | not' >/dev/null \
  && ok "prose mention (backtick-quoted) excluded" || bad "prose" "$WL"
printf '%s' "$WL" | jq -e '.[] | select(.file=="a.go") | .instruction == "handle the empty slice"' >/dev/null \
  && ok "go instruction parsed (leader stripped)" || bad "go instr" "$WL"
printf '%s' "$WL" | jq -e '.[] | select(.file=="d.html") | .instruction == "fix alt text"' >/dev/null \
  && ok "html instruction strips block closer" || bad "html instr" "$WL"
printf '%s' "$WL" | jq -e '.[] | select(.file=="b.swift") | .line == 1' >/dev/null \
  && ok "swift line number" || bad "swift line" "$WL"
printf '%s' "$WL" | jq -e 'all(.[]; .instruction != "")' >/dev/null \
  && ok "all instructions non-empty" || bad "instr non-empty" "$WL"
printf '%s' "$WL" | jq -e 'any(.[]; .file=="skip.ignored") | not' >/dev/null \
  && ok "gitignored file excluded" || bad "gitignore" "$WL"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
