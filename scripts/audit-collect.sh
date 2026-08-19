#!/usr/bin/env bash
# Monthly Claude-setup audit collector (Phase 0).
# Deterministic, READ-ONLY. Gathers raw facts into evidence files that the
# audit Workflow agents read — so agents never touch raw transcripts.
#
# Usage: audit-collect.sh [OUTPUT_DIR]
#   OUTPUT_DIR defaults to a fresh mktemp dir. The resolved dir is printed as
#   the LAST line of stdout (the skill captures it).
#
# Roots are overridable via env (for tests):
#   CLAUDE_HOME           (default $HOME/.claude)
#   SETUP_REPO            (default: resolved from this script's location)
#   CLAUDE_PROJECT_ROOTS  (default "$HOME", space-separated scan roots)
#   MEMORY_DIR            (default the claude-setup auto-memory dir)
#   WINDOW_DAYS           (default 30)   MAX_HITS (default 50)

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETUP_REPO="${SETUP_REPO:-$(CDPATH= cd -P "$(dirname "$0")" && cd .. && pwd)}"
REPO_SCAN_ROOTS="${CLAUDE_PROJECT_ROOTS:-$HOME}"
WINDOW_DAYS="${WINDOW_DAYS:-30}"
MAX_HITS="${MAX_HITS:-50}"

note() { printf '%s\n' "$*"; }
warn() { printf '_gap: %s_\n' "$*"; }

# is_mcp_referenced REPO MCP_FILES — true if REPO's path appears in any of the
# newline-separated .mcp.json files in MCP_FILES (i.e. the repo hosts an active
# MCP server). Such repos are in USE even when their git history is stale, so
# the dormancy check must not flag them as dead.
is_mcp_referenced() {
  local repo="$1" f
  while IFS= read -r f; do
    [ -n "$f" ] && grep -qF "$repo" "$f" 2>/dev/null && return 0
  done <<< "$2"
  return 1
}

collect_config() {
  note "# Config & artifact inventory"
  note

  local label dir found f entries
  for label in agents skills rules hooks; do
    dir="$SETUP_REPO/${label}"
    note "## ${label}"
    if [ -d "$dir" ]; then
      found=0
      entries=()
      case "$label" in
        skills) for f in "$dir"/*/SKILL.md; do [ -e "$f" ] && entries+=("$f"); done ;;
        hooks)  for f in "$dir"/*;          do [ -e "$f" ] && entries+=("$f"); done ;;
        *)      for f in "$dir"/*.md;        do [ -e "$f" ] && entries+=("$f"); done ;;
      esac
      # "${arr[@]+...}" guard: empty-array expansion is an unbound-variable
      # error under set -u on bash 3.2 (stock macOS /bin/bash).
      for f in "${entries[@]+${entries[@]}}"; do
        found=1
        note "- $(basename "${f%/SKILL.md}" .md)"
      done
      [ "$found" -eq 1 ] || warn "no $label entries"
    else
      warn "missing dir: $dir"
    fi
    note
  done

  note "## Slash commands (commands/ dirs under scan roots)"
  local r
  for r in $REPO_SCAN_ROOTS; do
    find "$r" -maxdepth 4 -type d -name commands \
      -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
  done | sort -u | sed 's|^|- |' || warn "command scan failed"
  note

  note "## Symlink integrity (config root)"
  local link target
  if [ -d "$CLAUDE_HOME" ]; then
    while IFS= read -r link; do
      target="$(readlink "$link")"
      if [ -e "$link" ]; then note "- OK   $link -> $target"
      else note "- DEAD $link -> $target"; fi
    done < <(find "$CLAUDE_HOME" -maxdepth 1 -type l 2>/dev/null | sort)
  else
    warn "config root missing: $CLAUDE_HOME"
  fi
  note

  note "## MCP servers registered in ~/.claude.json (user scope)"
  # Every MCP drift found in the 2026-08 audits lived HERE, invisible to the
  # old collector which only read .mcp.json (now empty by design).
  local cj="$CLAUDE_HOME/.claude.json"
  if [ -f "$cj" ]; then
    note "- $cj:"
    jq -r '.mcpServers // {} | to_entries[] | "  - \(.key): \(.value.command // .value.url // "?")"' "$cj" 2>/dev/null | while IFS= read -r l; do note "$l"; done
  fi
  note

  note "## Stale backups (*.bak.*)"
  local b mtime
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    # BSD stat's -f FORMAT and GNU stat's -f (--file-system) collide: on GNU,
    # the BSD invocation below still exits 1 but leaks filesystem-mode output
    # to stdout, so the fallback must be gated on its exit code, not `||`.
    mtime="$(stat -f '%Sm' -t '%Y-%m-%d' "$b" 2>/dev/null)"
    if [ $? -ne 0 ]; then mtime="$(stat -c '%y' "$b" 2>/dev/null | cut -d' ' -f1)"; fi
    note "- $b ($mtime)"
  done < <(find "$CLAUDE_HOME" -maxdepth 1 -name '*.bak.*' -type f 2>/dev/null)
  note

  note "## Debris counts (entries per dir)"
  local d
  for d in handoffs plans tasks teams session-env; do
    [ -d "$CLAUDE_HOME/$d" ] && \
      note "- $d: $(find "$CLAUDE_HOME/$d" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
  done
  note

  note "## Live agent processes"
  local procs
  procs="$(pgrep -fl 'agent-id' | head -"$MAX_HITS" || true)"
  if [ -n "$procs" ]; then printf '%s\n' "$procs" | awk '{print "- pid "$1}'
  else note "- none"; fi
  return 0
}
collect_friction() {
  note "# Friction & adoption (last ${WINDOW_DAYS}d)"
  note
  local proj="$CLAUDE_HOME/projects"
  if [ ! -d "$proj" ]; then warn "no projects dir: $proj"; return 0; fi

  local files
  files="$(find "$proj" -name '*.jsonl' -mtime "-${WINDOW_DAYS}" 2>/dev/null)"
  note "## Volume"
  note "- transcript files in window: $(printf '%s\n' "$files" | grep -c . || true)"
  note

  note "## Correction signatures (per project, sampled top ${MAX_HITS})"
  local pat='no,|don.?t|stop|again|actually|that.?s wrong|i said|not what'
  local f
  {
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # Skip agent-to-agent transcripts — their "user" turns are dispatch
      # prompts, not real user-correction friction.
      case "$f" in */subagents/*) continue ;; esac
      if grep -hE '"type":"user"' "$f" 2>/dev/null | grep -iqE "$pat"; then
        basename "$(dirname "$f")"
      fi
    done <<< "$files"
  } | sort | uniq -c | sort -rn | head -"$MAX_HITS" | sed 's|^|- |' || true
  note

  note "## Auto-compaction events (real boundaries, not the word)"
  local compact=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qE '"isCompactSummary"|"subtype":"compact_boundary"' "$f" 2>/dev/null; then
      compact=$((compact+1))
    fi
  done <<< "$files"
  note "- sessions with compaction boundary: $compact"
  note

  note "## Adoption — skills invoked"
  {
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -hoE '"skill":"[^"]+"' "$f" 2>/dev/null
    done <<< "$files"
  } | sort | uniq -c | sort -rn | head -"$MAX_HITS" | sed 's|^|- |' || true
  note

  note "## Adoption — subagent_type invoked"
  {
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -hoE '"subagent_type":"[^"]+"' "$f" 2>/dev/null
    done <<< "$files"
  } | sort | uniq -c | sort -rn | head -"$MAX_HITS" | sed 's|^|- |' || true
  note

  # Dormancy is computed HERE (not in a lane) because it is the cross-product of
  # the DEFINED inventory (claude-setup/{agents,skills}) and the INVOKED set
  # (this window's transcripts) — and no single lane agent reads both. Precompute
  # the invoked sets once (namespace stripped, e.g. "superpowers:brainstorming"
  # -> "brainstorming") to avoid an O(names x files) grep storm.
  note "## Dormancy — defined but not invoked (last ${WINDOW_DAYS}d)"
  note "_NB: artifacts added this window are 'not yet adopted', not necessarily dead — discount recent additions._"
  local name invoked_agents invoked_skills
  invoked_agents="$(while IFS= read -r f; do [ -n "$f" ] && grep -hoE '"subagent_type":"[^"]+"' "$f" 2>/dev/null; done <<< "$files" | sed -E 's/.*:"([^"]*:)?//; s/"$//' | sort -u)"
  invoked_skills="$(while IFS= read -r f; do [ -n "$f" ] && grep -hoE '"skill":"[^"]+"' "$f" 2>/dev/null; done <<< "$files" | sed -E 's/.*:"([^"]*:)?//; s/"$//' | sort -u)"
  note "### Agents (defined in claude-setup/agents, not seen as subagent_type)"
  for f in "$SETUP_REPO"/agents/*.md; do
    [ -e "$f" ] || break
    name="$(basename "$f" .md)"
    grep -qxF "$name" <<< "$invoked_agents" || note "- DORMANT agent: $name"
  done
  note "### Skills (defined in claude-setup/skills, not seen as skill invocation)"
  for f in "$SETUP_REPO"/skills/*/SKILL.md; do
    [ -e "$f" ] || break
    name="$(basename "$(dirname "$f")")"
    grep -qxF "$name" <<< "$invoked_skills" || note "- DORMANT skill: $name"
  done
  return 0
}
collect_memory() {
  note "# Memory & knowledge hygiene"
  note
  local memdir
  memdir="${MEMORY_DIR:-$CLAUDE_HOME/projects/$(printf '%s' "$SETUP_REPO" | sed 's#/#-#g')/memory}"

  if [ ! -d "$memdir" ]; then
    warn "memory dir missing: $memdir"
  else
    local idx="$memdir/MEMORY.md" f base ref wl name
    note "## Index integrity (files vs MEMORY.md)"
    for f in "$memdir"/*.md; do
      [ -e "$f" ] || break
      base="$(basename "$f")"
      [ "$base" = "MEMORY.md" ] && continue
      if [ -f "$idx" ] && grep -qF "($base)" "$idx"; then note "- OK indexed: $base"
      else note "- ORPHAN (no index line): $base"; fi
    done
    note

    note "## Dangling index links"
    if [ -f "$idx" ]; then
      grep -oE '\(([a-zA-Z0-9_.-]+\.md)\)' "$idx" 2>/dev/null | tr -d '()' \
        | while IFS= read -r ref; do
            [ -f "$memdir/$ref" ] || note "- DANGLING: $ref"
          done
    fi
    note

    note "## Dangling [[wikilinks]]"
    grep -rhoE '\[\[[a-zA-Z0-9_-]+\]\]' "$memdir" 2>/dev/null | sort -u \
      | while IFS= read -r wl; do
          name="$(printf '%s' "$wl" | tr -d '[]')"
          ls "$memdir/${name}"*.md >/dev/null 2>&1 || note "- $wl -> no matching file"
        done
    note

    note "## ERRORS.md vs 200-line cap"
    local errf="${ERRORS_FILE:-$memdir/ERRORS.md}"
    if [ -f "$errf" ]; then note "- ERRORS.md lines: $(wc -l < "$errf" | tr -d ' ') (cap 200)"
    else note "- ERRORS.md absent"; fi
    note
  fi

  note "## Date / staleness scan (dates found in memory + rules)"
  grep -rhoE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    "$memdir" "$SETUP_REPO/rules" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -"$MAX_HITS" | sed 's|^|- |' || true
  return 0
}
collect_cost() {
  note "# Cost & cross-repo consistency"
  note

  note "## Token/cost summary (stats-cache.json — best effort)"
  local stats="$CLAUDE_HOME/stats-cache.json"
  if [ -f "$stats" ]; then
    jq -r '
      if type=="object" then (keys[] | "- key: " + .)
      elif type=="array" then "- array length: " + (length|tostring)
      else "- scalar" end' "$stats" 2>/dev/null | head -"$MAX_HITS" \
      || warn "stats-cache.json present but not parseable"
  else
    warn "no stats-cache.json at $stats"
  fi
  note

  note "## Per-repo git-workflow.md drift vs canonical"
  local canon="$SETUP_REPO/rules/git-workflow.md" r gw
  if [ -f "$canon" ]; then
    for r in $REPO_SCAN_ROOTS; do
      while IFS= read -r gw; do
        diff -q "$canon" "$gw" >/dev/null 2>&1 || note "- DRIFT: $gw"
      done < <(find "$r" -maxdepth 6 -path '*/.claude/rules/git-workflow.md' 2>/dev/null)
    done
  else
    warn "canonical git-workflow.md missing: $canon"
  fi
  note

  note "## Dead-repo .claude configs (no git activity > 90d)"
  local cdir repo last now mcp_files days
  now="$(date +%s)"
  # Repos referenced by an active .mcp.json are in use even with stale commits
  # (e.g. vendored MCP servers) — collect the .mcp.json set once to exclude them.
  mcp_files="$(for r in $REPO_SCAN_ROOTS "$CLAUDE_HOME"; do
    find "$r" -maxdepth 5 -name '.mcp.json' -not -path '*/node_modules/*' 2>/dev/null
  done)"
  for r in $REPO_SCAN_ROOTS; do
    while IFS= read -r cdir; do
      repo="$(dirname "$cdir")"
      [ -d "$repo/.git" ] || continue
      last="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)"
      if [ "$last" -gt 0 ] && [ "$(( (now - last) / 86400 ))" -gt 90 ]; then
        days="$(( (now - last) / 86400 ))"
        if is_mcp_referenced "$repo" "$mcp_files"; then
          note "- USED (${days}d stale commits, referenced by .mcp.json): $repo"
        else
          note "- STALE (${days}d): $repo"
        fi
      fi
    done < <(find "$r" -maxdepth 5 -type d -name '.claude' \
               -not -path '*/node_modules/*' 2>/dev/null)
  done | head -"$MAX_HITS"
  note

  note "## MCP / plugin inventory + auth state"
  local mcp="$CLAUDE_HOME/.mcp.json"
  [ -f "$mcp" ] && note "- $mcp: $(jq -r '.mcpServers // {} | keys | join(", ")' "$mcp" 2>/dev/null || echo '?')"
  local authcache="$CLAUDE_HOME/mcp-needs-auth-cache.json"
  [ -f "$authcache" ] && note "- needs-auth: $(jq -r 'keys | join(", ")' "$authcache" 2>/dev/null || echo '?')"
  note

  note "## Enabled plugins (cross-ref for redundancy / project-scope creep)"
  local st="$CLAUDE_HOME/settings.json"
  if [ -f "$st" ]; then
    note "- $(jq -r '.enabledPlugins // {} | to_entries | map(select(.value)) | map(.key) | join(", ")' "$st" 2>/dev/null || echo '?')"
  else
    warn "no settings.json at $st"
  fi
  note

  # Prescribed-vs-USED: a configured MCP server with 0 actual tool-calls in the
  # window is a dead mandate or broken tooling (cf. the 2026-06 finding: leann
  # mandated in rules yet 0 calls — root cause was index rot + deferral friction).
  note "## MCP tools — prescribed vs USED (actual tool-calls, last ${WINDOW_DAYS}d)"
  local tfiles srv cnt
  tfiles="$(find "$CLAUDE_HOME/projects" -name '*.jsonl' -mtime "-${WINDOW_DAYS}" 2>/dev/null)"
  if [ -f "$mcp" ]; then
    for srv in $(jq -r '.mcpServers // {} | keys[]' "$mcp" 2>/dev/null); do
      cnt=$(while IFS= read -r f; do [ -n "$f" ] && grep -hoF "\"name\":\"mcp__${srv}__" "$f" 2>/dev/null; done <<< "$tfiles" | wc -l | tr -d ' ')
      note "- ${srv}: ${cnt} calls"
    done
  fi
  note

  note "## leann index health (stale indexes give degraded/garbage results)"
  local idxdir age nowts mtime
  nowts="$(date +%s)"
  for r in $REPO_SCAN_ROOTS; do
    # maxdepth 7: work indexes sit at depth 6 (work/coding/backend/<repo>/.leann/indexes/<name>)
    find "$r" -maxdepth 7 -type d -path '*/.leann/indexes/*' -not -path '*/node_modules/*' 2>/dev/null
  done | while IFS= read -r idxdir; do
    [ -n "$idxdir" ] || continue
    # Same BSD/GNU `stat -f` collision as the stale-backups check above: on GNU
    # the BSD form exits nonzero but still leaks filesystem-mode output to
    # stdout, so gate the fallback on the exit code rather than on `||`.
    mtime="$(stat -f %m "$idxdir" 2>/dev/null)"
    if [ $? -ne 0 ]; then mtime="$(stat -c %Y "$idxdir" 2>/dev/null)"; fi
    [ -n "$mtime" ] || mtime="$nowts"
    age=$(( (nowts - mtime) / 86400 ))
    if [ "$age" -gt 30 ]; then note "- STALE (${age}d): $idxdir"
    else note "- ok (${age}d): $idxdir"; fi
  done
  return 0
}

main() {
  # NOT set -e: collectors are best-effort by design — a missing dir/file is
  # skipped with a "_gap:" note, never fatal. -u/pipefail still catch real bugs.
  set -uo pipefail
  local out="${1:-$(mktemp -d "${TMPDIR:-/tmp}/claude-audit.XXXXXX")}"
  mkdir -p "$out"
  collect_config   > "$out/config.md"
  collect_friction > "$out/friction.md"
  collect_memory   > "$out/memory.md"
  collect_cost     > "$out/cost.md"
  printf '%s\n' "$out"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
