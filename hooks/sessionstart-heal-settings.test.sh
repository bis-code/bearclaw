#!/bin/sh
# Tests for sessionstart-heal-settings.sh (post copy-on-install: LIVE and
# CANON are always two independent real files — no symlink to assert or
# clobber). Uses CLAUDE_SETUP_REPO + CLAUDE_CONFIG_DIR seams to point at temp
# repo/root dirs instead of the real config.
HOOK="$(dirname "$0")/sessionstart-heal-settings.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Isolate the audit log too. The hook appends to
# $XDG_STATE_HOME/claude-memory/settings-heal.log; without this the suite
# writes into the developer's REAL state dir on every run. The seams above
# only redirect the repo and config root.
XDG_STATE_HOME="$TMP/state"; export XDG_STATE_HOME
CANON="$TMP/repo/settings.json"
LIVE="$TMP/root/settings.json"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

setup(){ rm -rf "$TMP/repo" "$TMP/root" "$XDG_STATE_HOME"; mkdir -p "$TMP/repo" "$TMP/root"; }
run(){ CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" >/dev/null 2>&1; }
run_out(){ CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" 2>/dev/null; }

# T1: LIVE identical to CANON -> no-op, no output, CANON untouched
setup
printf '{"effortLevel":"xhigh","model":"opus"}' > "$CANON"
printf '{"effortLevel":"xhigh","model":"opus"}' > "$LIVE"
out=$(run_out)
[ -z "$out" ] && ok "t1 identical: silent" || bad "t1 stdout" "$out"
[ "$(jq -r '.effortLevel' "$CANON")" = "xhigh" ] && ok "t1 canon untouched" || bad "t1 canon" "$(cat "$CANON")"

# T2: LIVE changed an allowlisted key -> merged into CANON, systemMessage emitted
setup
printf '{"effortLevel":"auto","model":"opus"}' > "$CANON"
printf '{"effortLevel":"xhigh","model":"opus"}' > "$LIVE"
out=$(run_out)
[ "$(jq -r '.effortLevel' "$CANON")" = "xhigh" ] && ok "t2 allowlisted key merged" || bad "t2 canon" "$(cat "$CANON")"
printf '%s' "$out" | grep -q systemMessage && ok "t2 emits systemMessage" || bad "t2 stdout" "$out"
[ -f "$LIVE" ] && [ "$(jq -r '.effortLevel' "$LIVE")" = "xhigh" ] && ok "t2 live untouched" || bad "t2 live" "$(cat "$LIVE")"

# T3: LIVE has a brand-new allowlisted key CANON lacks -> added to CANON
setup
printf '{"model":"opus"}' > "$CANON"
printf '{"model":"opus","theme":"dark"}' > "$LIVE"
run
[ "$(jq -r '.theme' "$CANON")" = "dark" ] && ok "t3 new allowlisted key added" || bad "t3 canon" "$(cat "$CANON")"

# T4: LIVE differs on `permissions` -> NEVER merged, even though it changed
setup
printf '{"model":"opus","permissions":{"allow":["Bash(ls:*)"]}}' > "$CANON"
printf '{"model":"opus","permissions":{"allow":["Bash(ls:*)","Bash(rm -rf /:*)"]}}' > "$LIVE"
out=$(run_out)
[ "$(jq -c '.permissions' "$CANON")" = '{"allow":["Bash(ls:*)"]}' ] && ok "t4 permissions NOT merged" || bad "t4 canon" "$(cat "$CANON")"
printf '%s' "$out" | grep -q systemMessage && bad "t4 should not report a merge" "$out" || ok "t4 no merge message (nothing allowlisted changed)"
grep -q "skipped.*permissions" "$XDG_STATE_HOME/claude-memory/settings-heal.log" 2>/dev/null && ok "t4 skip logged to audit trail" || bad "t4 audit log" "$(cat "$XDG_STATE_HOME/claude-memory/settings-heal.log" 2>/dev/null)"

# T5: LIVE differs on `env` -> not merged
setup
printf '{"model":"opus","env":{"A":"1"}}' > "$CANON"
printf '{"model":"opus","env":{"A":"2"}}' > "$LIVE"
run
[ "$(jq -r '.env.A' "$CANON")" = "1" ] && ok "t5 env NOT merged" || bad "t5 canon" "$(cat "$CANON")"

# T6: LIVE differs on `hooks` -> not merged
setup
printf '{"model":"opus","hooks":{"Stop":[]}}' > "$CANON"
printf '{"model":"opus","hooks":{"Stop":[{"hooks":[]}]}}' > "$LIVE"
run
[ "$(jq -c '.hooks' "$CANON")" = '{"Stop":[]}' ] && ok "t6 hooks NOT merged" || bad "t6 canon" "$(cat "$CANON")"

# T7: CANON missing -> exit 0, LIVE untouched
setup
printf '{"model":"opus"}' > "$LIVE"
run; rc=$?
[ "$rc" -eq 0 ] && ok "t7 exit 0 with no canon" || bad "t7 rc" "$rc"
[ "$(jq -r '.model' "$LIVE")" = "opus" ] && ok "t7 live untouched" || bad "t7 live" "$(cat "$LIVE")"

# T8: LIVE missing -> exit 0, CANON untouched
setup
printf '{"model":"opus"}' > "$CANON"
run; rc=$?
[ "$rc" -eq 0 ] && ok "t8 exit 0 with no live" || bad "t8 rc" "$rc"
[ "$(jq -r '.model' "$CANON")" = "opus" ] && ok "t8 canon untouched" || bad "t8 canon" "$(cat "$CANON")"

# T9: idempotent — a second run with nothing new to merge stays silent
setup
printf '{"model":"opus","effortLevel":"auto"}' > "$CANON"
printf '{"model":"opus","effortLevel":"xhigh"}' > "$LIVE"
run
out=$(run_out)
[ -z "$out" ] && ok "t9 idempotent second run: silent" || bad "t9" "$out"

# T10: multiple allowlisted keys change at once -> all merged, one message
setup
printf '{"model":"opus","effortLevel":"auto","theme":"light"}' > "$CANON"
printf '{"model":"sonnet","effortLevel":"xhigh","theme":"dark"}' > "$LIVE"
run
[ "$(jq -r '.model' "$CANON")" = "sonnet" ] && [ "$(jq -r '.effortLevel' "$CANON")" = "xhigh" ] && [ "$(jq -r '.theme' "$CANON")" = "dark" ] \
  && ok "t10 all changed allowlisted keys merged" || bad "t10 canon" "$(cat "$CANON")"

# T11: SETTINGS_HEAL_SILENT=1 suppresses the message but still merges
setup
printf '{"effortLevel":"auto"}' > "$CANON"
printf '{"effortLevel":"xhigh"}' > "$LIVE"
out=$(SETTINGS_HEAL_SILENT=1 CLAUDE_SETUP_REPO="$TMP/repo" CLAUDE_CONFIG_DIR="$TMP/root" bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "t11 silent mode emits nothing" || bad "t11 stdout" "$out"
[ "$(jq -r '.effortLevel' "$CANON")" = "xhigh" ] && ok "t11 silent mode still merges" || bad "t11 canon" "$(cat "$CANON")"

# T12: default (unset SETTINGS_HEAL_SILENT) still emits — SessionStart behaviour
setup
printf '{"effortLevel":"auto"}' > "$CANON"
printf '{"effortLevel":"xhigh"}' > "$LIVE"
out=$(run_out)
printf '%s' "$out" | grep -q systemMessage && ok "t12 default still emits systemMessage" || bad "t12 stdout" "$out"

# T13: REPO fallback resolves through a symlinked hooks dir to the REPO root,
# not to the symlink's parent (unchanged — the fallback line itself did not
# need to change here). Extracts the shipped assignment line and evaluates it
# from a symlinked path, which is how the hook is really invoked.
mkdir -p "$TMP/realrepo/hooks" "$TMP/link"
ln -s "$TMP/realrepo/hooks" "$TMP/link/hooks"
LINE=$(grep -m1 '^REPO=' "$HOOK")
{ printf '#!/bin/sh\n%s\nprintf %%s "$REPO"\n' "$LINE"; } > "$TMP/realrepo/hooks/probe.sh"
want=$(CDPATH= cd -P "$TMP/realrepo" && pwd)
got=$(env -u CLAUDE_SETUP_REPO sh "$TMP/link/hooks/probe.sh")
[ "$got" = "$want" ] && ok "t13 REPO fallback resolves through symlink to repo root" \
  || bad "t13 REPO symlink fallback" "got=$got want=$want"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
