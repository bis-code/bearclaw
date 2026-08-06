#!/bin/sh
# Tests for sessionstart-heal-settings.sh. Uses CLAUDE_SETUP_REPO + CLAUDE_CONFIG_DIR
# seams to point at temp repo/root dirs instead of the real config.
HOOK="$(dirname "$0")/sessionstart-heal-settings.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CANON="$TMP/repo/settings.json"
LIVE="$TMP/root/settings.json"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

setup(){ rm -rf "$TMP/repo" "$TMP/root"; mkdir -p "$TMP/repo" "$TMP/root"; }
run(){ CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" >/dev/null 2>&1; }

# T1: LIVE already a symlink to CANON -> no-op, CANON untouched
setup
printf '{"effortLevel":"xhigh"}' > "$CANON"
ln -s "$CANON" "$LIVE"
run
{ [ -L "$LIVE" ] && [ "$(readlink "$LIVE")" = "$CANON" ]; } && ok "t1 intact symlink left alone" || bad "t1 symlink" "$(ls -l "$LIVE")"
[ "$(jq -r '.effortLevel' "$CANON")" = "xhigh" ] && ok "t1 canon untouched" || bad "t1 canon" "$(cat "$CANON")"

# T2: real-file clobber (dropped effortLevel + a, changed model, added b) -> merge + re-symlink
setup
printf '{"effortLevel":"xhigh","model":"opus","a":1}' > "$CANON"
printf '{"model":"sonnet","b":2}' > "$LIVE"   # real file, not symlink
run
{ [ -L "$LIVE" ] && [ "$(readlink "$LIVE")" = "$CANON" ]; } && ok "t2 re-symlinked" || bad "t2 symlink" "$(ls -l "$LIVE")"
[ "$(jq -r '.effortLevel' "$CANON")" = "xhigh" ] && ok "t2 repo-only key restored" || bad "t2 effortLevel" "$(cat "$CANON")"
[ "$(jq -r '.model' "$CANON")" = "sonnet" ] && ok "t2 live value wins on overlap" || bad "t2 model" "$(cat "$CANON")"
[ "$(jq -r '.b' "$CANON")" = "2" ] && ok "t2 live-new key added" || bad "t2 b" "$(cat "$CANON")"
[ "$(jq -r '.a' "$CANON")" = "1" ] && ok "t2 repo-only key a preserved" || bad "t2 a" "$(cat "$CANON")"

# T3: broken symlink -> re-symlink to CANON (no merge)
setup
printf '{"effortLevel":"xhigh"}' > "$CANON"
ln -s "$TMP/gone.json" "$LIVE"   # dangling
run
{ [ -L "$LIVE" ] && [ "$(readlink "$LIVE")" = "$CANON" ]; } && ok "t3 broken symlink re-pointed" || bad "t3 symlink" "$(ls -l "$LIVE")"

# T4: CANON missing -> exit 0, LIVE untouched
setup
printf '{"x":1}' > "$LIVE"   # real file, no canon
run; rc=$?
[ "$rc" -eq 0 ] && ok "t4 exit 0 with no canon" || bad "t4 rc" "$rc"
{ [ -f "$LIVE" ] && [ ! -L "$LIVE" ]; } && ok "t4 live untouched" || bad "t4 live" "$(ls -l "$LIVE")"

# T5: resolving symlink to a NON-canon target (work->personal chain) -> left alone
setup
printf '{"effortLevel":"xhigh"}' > "$CANON"
printf '{"intermediate":true}' > "$TMP/other.json"
ln -s "$TMP/other.json" "$LIVE"
run
{ [ -L "$LIVE" ] && [ "$(readlink "$LIVE")" = "$TMP/other.json" ]; } && ok "t5 resolving symlink left alone" || bad "t5 symlink" "$(ls -l "$LIVE")"

# T6: sticky-key guard — intact symlink, but canon lost effortLevel that git
# HEAD has (write-through race) -> key restored from HEAD, other edits kept
setup
( cd "$TMP/repo" && git init -q && git config user.email t@t && git config user.name t )
printf '{"effortLevel":"auto","model":"opus"}' > "$CANON"
( cd "$TMP/repo" && git add settings.json && git commit -qm seed )
printf '{"model":"sonnet"}' > "$CANON"   # write-through dropped effortLevel, changed model
ln -s "$CANON" "$LIVE"
run
[ "$(jq -r '.effortLevel' "$CANON")" = "auto" ] && ok "t6 sticky key restored from HEAD" || bad "t6 effortLevel" "$(cat "$CANON")"
[ "$(jq -r '.model' "$CANON")" = "sonnet" ] && ok "t6 uncommitted edit kept" || bad "t6 model" "$(cat "$CANON")"

# T7: sticky key present with a CHANGED value -> left alone (only absence heals)
setup
( cd "$TMP/repo" && git init -q && git config user.email t@t && git config user.name t )
printf '{"effortLevel":"auto"}' > "$CANON"
( cd "$TMP/repo" && git add settings.json && git commit -qm seed )
printf '{"effortLevel":"high"}' > "$CANON"
ln -s "$CANON" "$LIVE"
run
[ "$(jq -r '.effortLevel' "$CANON")" = "high" ] && ok "t7 changed value untouched" || bad "t7 effortLevel" "$(cat "$CANON")"

# T8: key absent in HEAD too (deliberate committed removal) -> stays absent
setup
( cd "$TMP/repo" && git init -q && git config user.email t@t && git config user.name t )
printf '{"model":"opus"}' > "$CANON"
( cd "$TMP/repo" && git add settings.json && git commit -qm seed )
ln -s "$CANON" "$LIVE"
run
[ "$(jq -r 'has("effortLevel")' "$CANON")" = "false" ] && ok "t8 committed removal respected" || bad "t8 effortLevel" "$(cat "$CANON")"

# T9: nothing missing -> git is never invoked. This is what makes the hook
# affordable on Stop (every turn) rather than only at SessionStart.
run_path(){ PATH="$TMP/fakebin:$PATH" CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" >/dev/null 2>&1; }
setup
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\necho called >> "%s/git-calls"\nexit 0\n' "$TMP" > "$TMP/fakebin/git"
chmod +x "$TMP/fakebin/git"
rm -f "$TMP/git-calls"
printf '{"effortLevel":"auto"}' > "$CANON"
ln -s "$CANON" "$LIVE"
run_path
[ ! -f "$TMP/git-calls" ] && ok "t9 git not invoked when nothing is missing" || bad "t9 git called" "$(cat "$TMP/git-calls")"

# T9b: a key IS missing -> git is invoked (proves the pre-check gates, not blocks)
setup
rm -f "$TMP/git-calls"
printf '{"model":"opus"}' > "$CANON"
ln -s "$CANON" "$LIVE"
run_path
[ -f "$TMP/git-calls" ] && ok "t9b git invoked when a key is missing" || bad "t9b git not called" "no $TMP/git-calls"

# T10: silent mode repairs but emits nothing. Stop's stdout contract differs
# from SessionStart's, so a stray JSON payload there is a production-only bug.
setup
( cd "$TMP/repo" && git init -q && git config user.email t@t && git config user.name t )
printf '{"effortLevel":"auto","model":"opus"}' > "$CANON"
( cd "$TMP/repo" && git add settings.json && git commit -qm seed )
printf '{"model":"sonnet"}' > "$CANON"
ln -s "$CANON" "$LIVE"
out=$(SETTINGS_HEAL_SILENT=1 CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "t10 silent mode emits nothing" || bad "t10 stdout" "$out"
[ "$(jq -r '.effortLevel' "$CANON")" = "auto" ] && ok "t10 silent mode still repairs" || bad "t10 effortLevel" "$(cat "$CANON")"

# T11: silent mode also mutes the clobber-path message
setup
printf '{"effortLevel":"xhigh","model":"opus"}' > "$CANON"
printf '{"model":"sonnet"}' > "$LIVE"
out=$(SETTINGS_HEAL_SILENT=1 CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "t11 silent clobber path emits nothing" || bad "t11 stdout" "$out"
[ -L "$LIVE" ] && ok "t11 still re-symlinked" || bad "t11 symlink" "$(ls -l "$LIVE")"

# T12: default (unset) still emits — SessionStart behaviour is unchanged
setup
printf '{"effortLevel":"xhigh"}' > "$CANON"
printf '{"model":"sonnet"}' > "$LIVE"
out=$(CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" 2>/dev/null)
printf '%s' "$out" | grep -q systemMessage && ok "t12 default still emits systemMessage" || bad "t12 stdout" "$out"

# t: REPO fallback resolves through a symlinked hooks dir to the REPO root,
# not to the symlink's parent. Extracts the shipped assignment line and
# evaluates it from a symlinked path, which is how the hook is really invoked.
mkdir -p "$TMP/realrepo/hooks" "$TMP/link"
ln -s "$TMP/realrepo/hooks" "$TMP/link/hooks"
LINE=$(grep -m1 '^REPO=' "$HOOK")
{ printf '#!/bin/sh\n%s\nprintf %%s "$REPO"\n' "$LINE"; } > "$TMP/realrepo/hooks/probe.sh"
want=$(CDPATH= cd -P "$TMP/realrepo" && pwd)
got=$(env -u CLAUDE_SETUP_REPO sh "$TMP/link/hooks/probe.sh")
[ "$got" = "$want" ] && ok "REPO fallback resolves through symlink to repo root" \
  || bad "REPO symlink fallback" "got=$got want=$want"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
