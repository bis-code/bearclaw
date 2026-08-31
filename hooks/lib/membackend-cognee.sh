#!/bin/sh
# hooks/lib/membackend-cognee.sh — Cognee memory-backend CLI (STUB).
#
# This is the seam the Cognee stand-up task replaces internals of; until then
# every subcommand fails the same way so callers going through
# hooks/lib/memory-backend.sh see a plain "no backend" (exit 3) rather than a
# crash or silently-wrong results.
#
# Usage (CLI surface the real implementation must keep):
#   membackend-cognee.sh search <corpus-name> <query> <top-k>
#   membackend-cognee.sh dedup  <corpus-name> <candidate-file>
#   membackend-cognee.sh health
set +e
echo "cognee backend not configured on this machine" >&2
exit 3
