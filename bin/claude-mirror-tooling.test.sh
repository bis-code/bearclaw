#!/bin/sh
# Tests for claude-mirror-tooling: mirrors shared tooling DIRS from a src config
# root into a dst root (whole-dir symlink for agents/etc.; additive for skills),
# never touching account files (settings.json / .mcp.json / CLAUDE.md / ...).
BIN="$(cd "$(dirname "$0")" && pwd)/claude-mirror-tooling"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0; ok(){ echo "ok   $1"; }; bad(){ echo "FAIL $1 ($2)"; fail=1; }

SRC="$TMP/src"; DST="$TMP/dst"
mkdir -p "$SRC"/agents "$SRC"/commands "$SRC"/bin "$SRC"/rules "$SRC"/hooks "$SRC"/memory-global \
         "$SRC"/skills/handoff "$SRC"/skills/cost-report
printf 'cr' > "$SRC/agents/code-reviewer.md"
printf 'h'  > "$SRC/skills/handoff/SKILL.md"

# dst: root-specific skill + a pre-existing REAL commands dir (preserve) + account files (untouched)
mkdir -p "$DST"/skills/other-standup "$DST"/commands
printf 'WORK' > "$DST/skills/other-standup/SKILL.md"
printf 'WCMD' > "$DST/commands/work-cmd.md"
ln -s /work/.mcp.json "$DST/.mcp.json"
printf 'SET' > "$DST/settings.json"

OUT=$(sh "$BIN" "$SRC" "$DST" 2>&1)

# whole-dir symlinks for absent tooling
[ "$(readlink "$DST/agents")" = "$SRC/agents" ] && ok "agents whole-dir symlinked" || bad "agents" "$OUT"
[ "$(readlink "$DST/bin")" = "$SRC/bin" ] && ok "bin symlinked" || bad "bin" "$OUT"
[ "$(readlink "$DST/rules")" = "$SRC/rules" ] && ok "rules symlinked" || bad "rules" "$OUT"
[ "$(readlink "$DST/hooks")" = "$SRC/hooks" ] && ok "hooks symlinked" || bad "hooks" "$OUT"

# pre-existing REAL commands dir preserved (not clobbered)
{ [ ! -L "$DST/commands" ] && [ "$(cat "$DST/commands/work-cmd.md")" = "WCMD" ]; } && ok "real commands dir preserved" || bad "commands clobbered" "$OUT"

# skills additive: shared skills linked, root-specific skill preserved, dir stays real
[ -L "$DST/skills/handoff" ] && ok "skills/handoff linked (additive)" || bad "handoff" "$OUT"
[ -L "$DST/skills/cost-report" ] && ok "skills/cost-report linked" || bad "cost-report" "$OUT"
[ "$(cat "$DST/skills/other-standup/SKILL.md")" = "WORK" ] && ok "root-specific skill preserved" || bad "other-standup" "$OUT"
[ ! -L "$DST/skills" ] && ok "dst/skills stays a real dir" || bad "skills symlinked" "$OUT"

# global memory: per-root OWN dir (NOT a shared symlink to src) so nothing bleeds across roots
{ [ -d "$DST/memory-global" ] && [ ! -L "$DST/memory-global" ]; } && ok "memory-global own dir (not shared symlink)" || bad "memory-global shared/missing" "$OUT"
[ -f "$DST/memory-global/MEMORY.md" ] && ok "memory-global MEMORY.md seeded" || bad "mem index missing" "$OUT"
[ -f "$DST/memory-global/ERRORS.md" ] && ok "memory-global ERRORS.md seeded" || bad "mem errors missing" "$OUT"
printf 'SENTINEL' >> "$DST/memory-global/MEMORY.md"   # survives re-run iff not clobbered

# account files NEVER touched
[ "$(readlink "$DST/.mcp.json")" = "/work/.mcp.json" ] && ok ".mcp.json untouched" || bad ".mcp.json" "$OUT"
[ "$(cat "$DST/settings.json")" = "SET" ] && ok "settings.json untouched" || bad "settings" "$OUT"

# idempotent re-run
sh "$BIN" "$SRC" "$DST" >/dev/null 2>&1 && ok "idempotent re-run (exit 0)" || bad "rerun" "exit $?"
[ "$(readlink "$DST/agents")" = "$SRC/agents" ] && ok "agents still correct after re-run" || bad "rerun agents" ""
grep -q SENTINEL "$DST/memory-global/MEMORY.md" && ok "memory-global not clobbered on re-run" || bad "memory-global clobbered" ""

# usage error on missing args
sh "$BIN" "$SRC" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "missing arg -> usage exit 2" || bad "usage" "exit $?"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
