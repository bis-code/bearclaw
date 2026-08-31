#!/bin/sh
# hooks/lib/memory-roots.sh — where memory lives (SOURCED, not executed).
#
# There are two roots, and four callers that must agree on them exactly: the
# recall hook (searches them), SessionStart and Stop (keep their indexes fresh),
# and bin/claude-memory-recall (searches them by hand). Four copies of the same
# path arithmetic is how a tier ends up indexed under one name and searched
# under another — a silent miss, not an error. So the arithmetic lives here.
#
#   1. global   ~/.claude/memory-global/            — cross-cutting, every session
#   2. repo     <main-worktree>/.claude/memory/     — curated, git-tracked
#
# Claude Code 2.x also writes its own typed notes under
# ~/.claude/projects/<encoded-cwd>/memory/. This file deliberately does NOT
# index that directory: it is the harness's own machine-local store, and
# whether to treat it as a retrieval tier is a workflow decision for whoever
# installs this, not one to make on their behalf. Add a root here if you want
# it — memroots_emit is the only place that would change.
#
# Functions (each prints one value on stdout):
#   memroots_config_root
#   memroots_global_index / memroots_global_dir
#   memroots_main_root <cwd>       resolves a linked worktree to its main one
#   memroots_emit <cwd>            one "<index-name><TAB><dir>" line per root
#                                  that EXISTS; nothing for roots that do not

memroots_config_root() {
  printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# The global index name is derived from the active config root, so two configs
# on one machine get their own global memory instead of silently sharing one.
# Env override kept for tests.
memroots_global_index() {
  if [ -n "${GLOBAL_MEM_INDEX:-}" ]; then printf '%s\n' "$GLOBAL_MEM_INDEX"; return 0; fi
  printf '%s-memory-global\n' "$(basename "$(memroots_config_root)" | sed 's/^\.//')"
}

memroots_global_dir() {
  if [ -n "${GLOBAL_MEM_DIR:-}" ]; then printf '%s\n' "$GLOBAL_MEM_DIR"; return 0; fi
  printf '%s/memory-global\n' "$(memroots_config_root)"
}

# Memory lives in the MAIN worktree, not in linked ones, so every worktree of a
# repo shares one index instead of each building its own from a directory that
# is not there.
memroots_main_root() { # $1 = cwd
  _mr_cwd="$1"
  [ -n "$_mr_cwd" ] || { printf '\n'; return 0; }
  _mr_common=$(git -C "$_mr_cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$_mr_common" ]; then
    printf '%s\n' "$(dirname "$_mr_common")"
  else
    printf '%s\n' "$_mr_cwd"
  fi
}

# Every root that exists, as "<index-name><TAB><dir>". A caller iterating this
# needs no knowledge of which tiers there are.
memroots_emit() { # $1 = cwd
  _me_cwd="$1"

  _me_gdir=$(memroots_global_dir)
  [ -d "$_me_gdir" ] && printf '%s\t%s\n' "$(memroots_global_index)" "$_me_gdir"

  [ -n "$_me_cwd" ] || return 0
  _me_main=$(memroots_main_root "$_me_cwd")
  [ -n "$_me_main" ] || return 0

  # Curated repo tier. Named <basename>-memory, the convention already on disk.
  if [ -d "$_me_main/.claude/memory" ]; then
    printf '%s-memory\t%s\n' "$(basename "$_me_main")" "$_me_main/.claude/memory"
  elif [ -d "$_me_cwd/.claude/memory" ]; then
    # Not a git repo, or the memory dir lives in the cwd rather than the main
    # worktree. Fall back so a plain directory with memory still gets a tier.
    printf '%s-memory\t%s\n' "$(basename "$_me_cwd")" "$_me_cwd/.claude/memory"
  fi
  return 0
}
