#!/usr/bin/env bash
# memory-doctor.sh — validate/fix one memory dir's index + ERRORS cap.
#
# Usage: memory-doctor.sh [--apply] [DIR]
#   DIR defaults to $HOME/.claude/memory-global. Run per-tier (pass a repo's
#   .claude/memory to check repo-local memory).
#   Report mode (default) is READ-ONLY. --apply performs SAFE fixes only:
#   removes dangling index lines, appends REVIEW-marked stubs for orphan entry
#   files. NEVER deletes entry files, rotates ERRORS, or prunes notes.
#
# Env (tests): ERRORS_CAP (default 200), STALE_DAYS (default 60).

note() { printf '%s\n' "$*"; }

APPLY=0
DIR=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) DIR="$arg" ;;
  esac
done
DIR="${DIR:-$HOME/.claude/memory-global}"
ERRORS_CAP="${ERRORS_CAP:-200}"
STALE_DAYS="${STALE_DAYS:-60}"

# fm_value FILE KEY — print the YAML-frontmatter value for KEY (first match),
# stripping surrounding quotes. Empty if absent or no frontmatter.
fm_value() {
  awk -v k="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && index($0, k":")==1 {
      sub("^"k":[[:space:]]*", ""); gsub(/^"|"$/, ""); print; exit
    }
  ' "$1"
}

main() {
  set -uo pipefail
  note "# memory-doctor — $DIR ($([ "$APPLY" -eq 1 ] && echo APPLY || echo report))"
  if [ ! -d "$DIR" ]; then note "_no memory dir: ${DIR}_"; return 0; fi
  scan_index "$DIR"
  scan_errors "$DIR"
  scan_stale "$DIR"
  return 0
}

scan_index() {
  local dir="$1" idx="$1/MEMORY.md" f base ref nm desc
  note
  note "## Index integrity"
  [ -f "$idx" ] || note "- (no MEMORY.md)"

  for f in "$dir"/*.md; do
    [ -e "$f" ] || break
    base="$(basename "$f")"
    case "$base" in MEMORY.md|ERRORS.md|ERRORS.archive.md|README.md) continue ;; esac
    nm="$(fm_value "$f" name)"; desc="$(fm_value "$f" description)"
    if [ -z "$nm" ] || [ -z "$desc" ]; then
      note "- MALFORMED: $base (missing name/description frontmatter)"
    fi
    if [ -f "$idx" ] && grep -qF "($base)" "$idx"; then :; else
      if [ "$APPLY" -eq 1 ] && [ -f "$idx" ]; then
        printf -- '- [%s](%s) — %s  <!-- REVIEW: refine title/hook -->\n' \
          "${nm:-$base}" "$base" "${desc:-(no description)}" >> "$idx"
        note "- FIXED orphan: appended REVIEW stub for $base"
      else
        note "- ORPHAN: $base (no index line)"
      fi
    fi
  done

  if [ -f "$idx" ]; then
    grep -oE '\(([a-zA-Z0-9_.-]+\.md)\)' "$idx" 2>/dev/null | tr -d '()' | sort -u \
      | while IFS= read -r ref; do
          if [ ! -f "$dir/$ref" ]; then
            if [ "$APPLY" -eq 1 ]; then
              grep -vF "($ref)" "$idx" > "$idx.tmp" && mv "$idx.tmp" "$idx"
              note "- FIXED dangling: removed line(s) for $ref"
            else
              note "- DANGLING: $ref"
            fi
          fi
        done
  fi
  return 0
}
scan_errors() {
  local dir="$1" errf="$1/ERRORS.md" lines
  [ -f "$errf" ] || return 0
  lines="$(wc -l < "$errf" | tr -d ' ')"
  note
  note "## ERRORS.md ($lines lines, cap $ERRORS_CAP)"
  if [ "$lines" -gt "$ERRORS_CAP" ]; then
    note "- over cap — rotate oldest entries to ERRORS.archive.md per rules/memory-hygiene.md (manual; auto-rotation not built — no journal is near the cap)"
  else
    note "- within cap"
  fi
  return 0
}
scan_stale() {
  local dir="$1" f base oldest now d epoch
  now="$(date +%s)"
  note
  note "## Stale-note candidates (dated > ${STALE_DAYS}d; report-only, never auto-pruned)"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || break
    base="$(basename "$f")"
    case "$base" in ERRORS.md|ERRORS.archive.md) continue ;; esac
    oldest="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | sort | head -1)"
    [ -n "$oldest" ] || continue
    epoch="$(date -j -f '%Y-%m-%d' "$oldest" +%s 2>/dev/null || echo 0)"
    [ "$epoch" -gt 0 ] || continue
    d="$(( (now - epoch) / 86400 ))"
    [ "$d" -gt "$STALE_DAYS" ] && note "- STALE-CANDIDATE: $base (oldest date $oldest, ${d}d ago)"
  done
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
