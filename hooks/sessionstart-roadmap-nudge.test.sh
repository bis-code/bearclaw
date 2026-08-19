#!/bin/sh
# Tests for sessionstart-roadmap-nudge.sh — gh is stubbed via GH_BIN.
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "ok   $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL $1 ($2)"; FAIL=$((FAIL+1)); }

# gh stub: emits one "now" issue and one "next" issue depending on --label
cat > "$TMP/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *"--label now"*)  printf -- '- #12 Ship the widget\n' ;;
  *"--label next"*) printf -- '- #13 Polish the frob\n' ;;
esac
EOF
chmod +x "$TMP/gh"
cat > "$TMP/gh-empty" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/gh-empty"

R="$TMP/proj"; mkdir -p "$R"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m x && git remote add origin https://github.com/x/y.git )
NOGH="$TMP/nogit"; mkdir -p "$NOGH"

run(){ printf '{"cwd":"%s"}' "$1" | ROADMAP_FORCE=1 GH_BIN="$2" \
  XDG_STATE_HOME="$TMP/state" sh "$DIR/sessionstart-roadmap-nudge.sh"; }

# t1: repo + github remote + issues -> injects roadmap with both sections
out=$(run "$R" "$TMP/gh")
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "#12 Ship the widget" && ok "t1 now issues injected" || bad "t1" "$out"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "#13 Polish the frob" && ok "t1 next issues injected" || bad "t1n" "$out"

# t2: no issues -> silent
out=$(run "$R" "$TMP/gh-empty")
[ -z "$out" ] && ok "t2 no issues: silent" || bad "t2" "$out"

# t3: not a git repo -> silent
out=$(run "$NOGH" "$TMP/gh")
[ -z "$out" ] && ok "t3 non-repo silent" || bad "t3" "$out"

# t4: non-github remote -> silent
R2="$TMP/gitlab"; mkdir -p "$R2"
( cd "$R2" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m x && git remote add origin https://gitlab.com/x/y.git )
out=$(run "$R2" "$TMP/gh")
[ -z "$out" ] && ok "t4 non-github remote silent" || bad "t4" "$out"

# t5: throttle — second run same day without FORCE is silent
printf '{"cwd":"%s"}' "$R" | GH_BIN="$TMP/gh" XDG_STATE_HOME="$TMP/state-t5" sh "$DIR/sessionstart-roadmap-nudge.sh" >/dev/null
out=$(printf '{"cwd":"%s"}' "$R" | GH_BIN="$TMP/gh" XDG_STATE_HOME="$TMP/state-t5" sh "$DIR/sessionstart-roadmap-nudge.sh")
[ -z "$out" ] && ok "t5 once-daily throttle" || bad "t5" "$out"

# t6: under a ROADMAP_SKIP_ROOTS prefix -> silent
FH="$TMP/home"; mkdir -p "$FH/readonly/proj"
( cd "$FH/readonly/proj" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m x && git remote add origin https://github.com/w/w.git )
out=$(printf '{"cwd":"%s"}' "$FH/readonly/proj" | ROADMAP_SKIP_ROOTS="$FH/readonly" \
  ROADMAP_FORCE=1 GH_BIN="$TMP/gh" XDG_STATE_HOME="$TMP/state" \
  sh "$DIR/sessionstart-roadmap-nudge.sh")
[ -z "$out" ] && ok "t6 skip-root silent" || bad "t6" "$out"

# t6b: same repo, no ROADMAP_SKIP_ROOTS -> NOT silent (proves t6 is the seam
# doing the work, not an unrelated early exit)
out=$(printf '{"cwd":"%s"}' "$FH/readonly/proj" | ROADMAP_FORCE=1 GH_BIN="$TMP/gh" \
  XDG_STATE_HOME="$TMP/state-t6b" sh "$DIR/sessionstart-roadmap-nudge.sh")
[ -n "$out" ] && ok "t6b no skip-root -> nudges" || bad "t6b" "(empty)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
