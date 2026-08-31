#!/bin/sh
# Rebuild memory indexes if a memory file changed (freshness is mtime-gated, so
# this is cheap). Runs for EVERY root — the repo tier is where a note written
# this session most often lands, and it used to be the one tier never refreshed
# here, so a memory captured mid-session stayed unsearchable until some later
# SessionStart happened to notice it.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
# cwd from the process, not from stdin. A `cat` here blocks forever whenever
# stdin happens to be a terminal instead of the harness's JSON — which is how
# the test suite invokes hooks — and the hook already runs in the project
# directory, so reading the payload would buy nothing.
CWD=$(pwd)
if [ -f "$DIR/lib/memory-roots.sh" ]; then
  . "$DIR/lib/memory-roots.sh"
  while IFS="	" read -r _fi _fd; do
    [ -n "$_fi" ] || continue
    sh "$DIR/memory-index-freshness.sh" "$_fi" "$_fd" >/dev/null 2>&1 &
  done <<EOF
$(memroots_emit "$CWD")
EOF
fi
exit 0
