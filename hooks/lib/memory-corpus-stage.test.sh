set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); SRC="$TMP/src"; STAGE="$TMP/stage"; mkdir -p "$SRC"
printf -- '---\nname: foo\n---\nbody one\n' > "$SRC/entry-foo.md"
printf -- '# ERRORS\n\n## [2026-01-01] boom — fixed\n- Fix: x\n\n## [2026-02-02] bang — fixed\n- Fix: y\n' > "$SRC/ERRORS.md"
printf -- 'index pointer line\n' > "$SRC/MEMORY.md"
sh "$DIR/memory-corpus-stage.sh" "$SRC" "$STAGE"
# curated entry copied
[ -f "$STAGE/entry-foo.md" ] || { echo "FAIL: entry-foo missing"; exit 1; }
# ERRORS split into 2 units
n=$(ls "$STAGE"/errors__*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "2" ] || { echo "FAIL: expected 2 error chunks, got $n"; exit 1; }
# MEMORY.md excluded; whole ERRORS.md not present
[ ! -f "$STAGE/MEMORY.md" ] || { echo "FAIL: MEMORY.md should be excluded"; exit 1; }
[ ! -f "$STAGE/ERRORS.md" ] || { echo "FAIL: whole ERRORS.md should not be staged"; exit 1; }
echo "PASS"
