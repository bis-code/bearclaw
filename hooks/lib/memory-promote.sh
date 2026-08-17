#!/bin/sh
# memory-promote.sh <entry-file.md> [--dry-run] [--force]
# Promote a machine-local memory entry into the committed memory-global/ tier —
# the ONLY path by which a lesson captured on one machine reaches the others.
# Flow: dedup vs the global index → copy entry → append MEMORY.md index line →
# print the exact commit+push command (promotion is not durable until pushed).
# Exit: 0 promoted · 1 usage/error · 3 near-duplicate (SKIP) · 4 grep-hit under
# UNVERIFIED (use --force after review).
# Seams (tests): GLOBAL_MEM_DIR, GLOBAL_MEM_INDEX, MEMORY_SEARCH_CMD (dedup stub).
set -u

ENTRY="${1:-}"; shift 2>/dev/null || true
DRY=0; FORCE=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --force) FORCE=1 ;; esac
done
[ -n "$ENTRY" ] && [ -f "$ENTRY" ] || { echo "usage: memory-promote.sh <entry-file.md> [--dry-run] [--force]" >&2; exit 1; }

GDIR="${GLOBAL_MEM_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-global}"
GIDX="${GLOBAL_MEM_INDEX:-$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')-memory-global}"
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)

BASE=$(basename "$ENTRY")
SLUG="${BASE%.md}"
# Title: frontmatter name:, else first heading, else slug.
TITLE=$(sed -n 's/^name:[[:space:]]*//p' "$ENTRY" | head -1)
[ -n "$TITLE" ] || TITLE=$(sed -n 's/^#[[:space:]]*//p' "$ENTRY" | head -1)
[ -n "$TITLE" ] || TITLE="$SLUG"
# Hook line: frontmatter description:, else first non-empty body line.
HOOK=$(sed -n 's/^description:[[:space:]]*//p' "$ENTRY" | head -1)
[ -n "$HOOK" ] || HOOK=$(grep -v '^---\|^#\|^$\|^name:\|^metadata\|^  ' "$ENTRY" | head -1 | cut -c1-150)

[ -e "$GDIR/$SLUG.md" ] && { echo "FAIL $GDIR/$SLUG.md already exists — update it in place instead"; exit 1; }

CAND="$TITLE $HOOK $(head -c 400 "$ENTRY" | tr '\n' ' ')"
VERDICT=$(sh "$DIR/memory-dedup.sh" "$GIDX" "$CAND" 2>/dev/null)
case "$VERDICT" in
  *SKIP*)
    echo "SKIP near-duplicate already in global memory (dedup: $VERDICT) — bump the existing entry's verified date instead"
    exit 3 ;;
  *UNVERIFIED*)
    echo "note: semantic dedup unavailable ($VERDICT) — falling back to literal grep"
    HITS=$(grep -ril "$SLUG" "$GDIR" 2>/dev/null | head -3)
    if [ -n "$HITS" ] && [ "$FORCE" -eq 0 ]; then
      echo "grep found possible duplicates — review, then re-run with --force:"
      printf '%s\n' "$HITS"
      exit 4
    fi ;;
esac

LINE="- [$TITLE]($SLUG.md) — $HOOK"
if [ "$DRY" -eq 1 ]; then
  echo "would: cp $ENTRY $GDIR/$SLUG.md"
  echo "would: append to $GDIR/MEMORY.md: $LINE"
  echo "would print commit command"
  exit 0
fi

cp "$ENTRY" "$GDIR/$SLUG.md"
printf '%s\n' "$LINE" >> "$GDIR/MEMORY.md"
REPO=$(dirname "$(readlink -f "$GDIR/MEMORY.md")")
REPO=$(cd "$REPO/.." && pwd)
echo "promoted: $GDIR/$SLUG.md (+ index line)"
echo "now commit + push (promotion reaches other machines only after this):"
echo "  git -C $REPO add memory-global/$SLUG.md memory-global/MEMORY.md && git -C $REPO commit -m 'docs(memory): promote $SLUG' && git -C $REPO push"
