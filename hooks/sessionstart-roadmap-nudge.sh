#!/bin/sh
# sessionstart-roadmap-nudge.sh — SessionStart: in a personal project repo with
# a GitHub remote, inject the now/next issue roadmap once daily per repo — the
# roadmap greets you instead of being fetched (docs-gate convertible,
# 2026-08-17; mechanizes USAGE.md's session-start step).
# Silent when: not a git repo, no GitHub remote, under an opted-out root,
# gh missing, or no now/next issues.
# ROADMAP_SKIP_ROOTS: colon-separated absolute path prefixes to stay silent
# under — for repos tracked somewhere other than GitHub Issues, or that you
# only ever read. Empty by default: this hook assumes nothing about your
# directory layout.
# Seams (tests): ROADMAP_FORCE=1 (skip throttle), XDG_STATE_HOME, GH_BIN.
set +e

INPUT=$(cat 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
IFS=':'
for _root in ${ROADMAP_SKIP_ROOTS:-}; do
  [ -n "$_root" ] || continue
  case "$CWD" in "$_root"*) exit 0 ;; esac
done
unset IFS _root

git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 || exit 0
URL=$(git -C "$CWD" remote get-url origin 2>/dev/null)
case "$URL" in *github.com*) ;; *) exit 0 ;; esac

GH="${GH_BIN:-gh}"
command -v "$GH" >/dev/null 2>&1 || exit 0

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
KEY=$(printf '%s' "$ROOT" | cksum 2>/dev/null | cut -d' ' -f1)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory"
mkdir -p "$STATE" 2>/dev/null
STAMP="$STATE/roadmap.$KEY.$(date +%Y-%m-%d)"
if [ "${ROADMAP_FORCE:-0}" != "1" ]; then
  [ -f "$STAMP" ] && exit 0
fi
: > "$STAMP" 2>/dev/null
find "$STATE" -maxdepth 1 -name "roadmap.$KEY.*" ! -name "$(basename "$STAMP")" -delete 2>/dev/null

NOW=$(cd "$CWD" && "$GH" issue list --label now --state open --limit 5 \
  --json number,title --jq '.[] | "- #\(.number) \(.title)"' 2>/dev/null)
NEXT=$(cd "$CWD" && "$GH" issue list --label next --state open --limit 5 \
  --json number,title --jq '.[] | "- #\(.number) \(.title)"' 2>/dev/null)
[ -z "$NOW" ] && [ -z "$NEXT" ] && exit 0

OUT="## Roadmap ($(basename "$ROOT"), from GitHub issues)
"
[ -n "$NOW" ] && OUT="${OUT}**now:**
$NOW
"
[ -n "$NEXT" ] && OUT="${OUT}**next:**
$NEXT
"
OUT="${OUT}Reconcile against git state before starting; flip issues at session end (status-flip rule)."

jq -n --arg ctx "$OUT" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
