#!/bin/sh
# Rebuild the memory index if a memory file changed (freshness is mtime-gated, so this is cheap).
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
GLOBAL_MEM_DIR="${GLOBAL_MEM_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory-global}"
GLOBAL_MEM_INDEX="${GLOBAL_MEM_INDEX:-$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')-memory-global}"
sh "$DIR/memory-index-freshness.sh" "$GLOBAL_MEM_INDEX" "$GLOBAL_MEM_DIR" >/dev/null 2>&1 &
exit 0
