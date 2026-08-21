#!/bin/sh
# Tests for stop-memory-index-rebuild.sh — the Stop-hook wrapper that
# backgrounds memory-index-freshness.sh to rebuild the memory semantic index.
# The rebuild is mtime-gated by memory-index-freshness.sh: a no-op (no leann
# call) when no memory .md file is newer than the last-built stamp, so this
# hook is cheap to run on every Stop event. Covers both directions: a rebuild
# fires when warranted, and stays quiet (no leann call) when nothing changed.
#
# CRITICAL: unstubbed, this hook drives the real `leann build` command against
# this machine's real semantic-memory index (see CONTRIBUTING.md rule 5, and
# scripts/tests/install.bats for the reference pattern). Every invocation below
# MUST set MEMORY_BUILD_CMD / GLOBAL_MEM_INDEX / XDG_STATE_HOME so no test can
# reach the real leann build or the real freshness stamp.
HOOK="$(dirname "$0")/stop-memory-index-rebuild.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1 ($2)"; fail=1; }

MEM_DIR="$TMP/mem"; mkdir -p "$MEM_DIR"
STATE_DIR="$TMP/state"
MARKER="$TMP/build-marker"
BUILD_CMD="$TMP/fake-build.sh"
cat > "$BUILD_CMD" <<BUILDEOF
#!/bin/sh
echo built >> "$MARKER"
BUILDEOF
chmod +x "$BUILD_CMD"

SAFE="GLOBAL_MEM_DIR=$MEM_DIR GLOBAL_MEM_INDEX=test-memory-global MEMORY_BUILD_CMD=$BUILD_CMD XDG_STATE_HOME=$STATE_DIR"

run() { printf '{}' | env $SAFE sh "$HOOK"; }

marker_lines() {
    if [ -f "$MARKER" ]; then
        wc -l < "$MARKER" | tr -d ' '
    else
        echo 0
    fi
}

# The hook backgrounds its work (`sh memory-index-freshness.sh ... &`) and
# exits 0 immediately, so a fired rebuild is asserted by polling briefly
# rather than checking synchronously right after the hook returns.
# Budget 10s, not 2s. The poll returns the instant the count is reached, so a
# generous ceiling costs a passing run nothing — but what it waits on is a
# BACKGROUNDED job competing with ~38 other suites and whatever else the machine
# is doing, and a 2s ceiling turns ordinary load into a red suite. A gate that
# goes red for reasons unrelated to the code is a gate people learn to bypass.
wait_for_count() {
    want="$1"; n=0
    while [ "$n" -lt 200 ]; do
        [ "$(marker_lines)" -ge "$want" ] && return 0
        n=$((n + 1)); sleep 0.05
    done
    return 1
}

# t1: the hook itself exits 0 and prints nothing (its output is backgrounded
# and redirected to /dev/null; only the freshness gate underneath can build)
out=$(run); rc=$?
[ "$rc" -eq 0 ] && ok "t1 exits 0" || bad "t1 rc" "$rc"
[ -z "$out" ] && ok "t1 no stdout from the hook itself" || bad "t1 stdout" "$out"

# t2: no freshness stamp yet -> first run always rebuilds
wait_for_count 1 && ok "t2 first run rebuilds (no stamp yet)" || bad "t2" "marker lines=$(marker_lines)"

# t3: re-run with nothing changed -> mtime-gated, no rebuild (stays cheap)
run >/dev/null
sleep 0.3   # give a wrongly-firing background job a chance to land before asserting silence
[ "$(marker_lines)" -eq 1 ] && ok "t3 unchanged: no rebuild" || bad "t3" "marker lines=$(marker_lines)"

# t4: a memory file newer than the stamp -> rebuilds again
sleep 1   # ensure a distinguishable mtime past the stamp written in t2
printf '# note\n' > "$MEM_DIR/a.md"
run >/dev/null
wait_for_count 2 && ok "t4 changed memory file triggers rebuild" || bad "t4" "marker lines=$(marker_lines)"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
