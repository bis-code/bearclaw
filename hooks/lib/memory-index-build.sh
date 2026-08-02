#!/bin/sh
# memory-index-build.sh <index-name> <src-memory-dir>
set -e
NAME="$1"; SRC="$2"
STAGE="${TMPDIR:-/tmp}/${NAME}-stage"
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
sh "$DIR/memory-corpus-stage.sh" "$SRC" "$STAGE"
[ -n "$(ls -A "$STAGE" 2>/dev/null)" ] || exit 0   # empty corpus -> nothing to build
( cd "$HOME" && leann build "$NAME" --docs "$STAGE" --file-types .md \
    --doc-chunk-size 512 --doc-chunk-overlap 64 --force >/dev/null 2>&1 )
