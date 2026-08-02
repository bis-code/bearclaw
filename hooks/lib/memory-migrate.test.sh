#!/bin/sh
# memory-migrate.test.sh — additive copy, skip-existing, build-invoked.
set -e
SCRIPT=$(CDPATH= cd "$(dirname "$0")" && pwd)/memory-migrate.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude/memory"
printf 'canon body\n' > "$PROJ/.claude/memory/dup.md"   # existing canonical entry

ENCODED=$(printf '%s' "$PROJ" | sed 's:/:-:g')
LEGACY="$TMP/.claude/projects/$ENCODED/memory"
mkdir -p "$LEGACY"
printf 'legacy version\n' > "$LEGACY/dup.md"            # same name, different content
printf 'brand new entry\n' > "$LEGACY/new.md"           # legacy-only -> should migrate

OUT=$(cd "$PROJ" && HOME="$TMP" MEMORY_BUILD_CMD=true sh "$SCRIPT")

# 1) new entry copied into canonical
[ -f "$PROJ/.claude/memory/new.md" ] || fail "new.md not migrated into canonical"
grep -q 'brand new entry' "$PROJ/.claude/memory/new.md" || fail "new.md content wrong"

# 2) existing canonical entry NOT clobbered by legacy
grep -q 'canon body' "$PROJ/.claude/memory/dup.md" || fail "dup.md was clobbered (must keep canonical)"

# 3) legacy left intact (additive copy, not move)
[ -f "$LEGACY/new.md" ] || fail "legacy new.md was deleted (must be non-destructive)"

# 4) summary reports moved 1 / skipped 1 / build yes
printf '%s' "$OUT" | grep -q 'moved 1 new' || fail "summary missing 'moved 1 new': $OUT"
printf '%s' "$OUT" | grep -q 'skipped 1 existing' || fail "summary missing 'skipped 1 existing': $OUT"
printf '%s' "$OUT" | grep -q 'build=yes' || fail "summary missing 'build=yes': $OUT"

# 5) no legacy dir -> still builds, moved 0
PROJ2="$TMP/proj2"; mkdir -p "$PROJ2/.claude/memory"
printf 'x\n' > "$PROJ2/.claude/memory/a.md"
OUT2=$(cd "$PROJ2" && HOME="$TMP" MEMORY_BUILD_CMD=true sh "$SCRIPT")
printf '%s' "$OUT2" | grep -q 'moved 0 new' || fail "no-legacy: expected 'moved 0 new': $OUT2"
printf '%s' "$OUT2" | grep -q 'build=yes' || fail "no-legacy: expected build=yes: $OUT2"

echo "ALL PASS"
