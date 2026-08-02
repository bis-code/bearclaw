#!/bin/sh
# memory-corpus-stage.sh <src-memory-dir> <stage-dir>
# Stages the recall corpus: curated per-file entries + per-entry ERRORS chunks.
set -e
SRC="$1"; STAGE="$2"
[ -d "$SRC" ] || exit 0
rm -rf "$STAGE"; mkdir -p "$STAGE"

# 1) curated per-file entries (exclude index, archive, handoffs, the ERRORS monolith)
for f in "$SRC"/*.md; do
  [ -f "$f" ] || continue
  base=${f##*/}
  case "$base" in
    MEMORY.md|ERRORS.md|ERRORS.archive.md|README.md) continue ;;
  esac
  cp "$f" "$STAGE/$base"
done

# 2) split ERRORS.md on '## ' headers -> one file per entry
if [ -f "$SRC/ERRORS.md" ]; then
  awk -v stage="$STAGE" '
    /^## / {
      n++; slug=sprintf("%04d", n);
      fname=stage "/errors__" slug ".md";
      print > fname; next
    }
    n>0 { print >> fname }
  ' "$SRC/ERRORS.md"
fi
