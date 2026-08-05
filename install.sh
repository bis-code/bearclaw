#!/usr/bin/env bash
set -euo pipefail
# Symlinks this repo into ~/.claude/. Editing ~/.claude/X = editing repo X.
# Idempotent: safe to re-run after `git pull`. Backs up real files once.
#
# Usage:
#   ./install.sh [DEST]              install (DEST defaults to ~/.claude)
#   ./install.sh --dry-run [DEST]    print what would happen, change nothing
#   ./install.sh --uninstall [DEST]  remove only the symlinks this script made
#
# This script touches ONLY $DEST and $XDG_STATE_HOME/claude-memory. It never
# modifies your global git config, your ~/.gitconfig, or your shell rc files.

DRY=0; MODE=install
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1; shift ;;
    --uninstall) MODE=uninstall; shift ;;
    -h|--help)   sed -n '3,12p' "$0"; exit 0 ;;
    *)           break ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/.claude}"
BACKUP="$DEST/backups/pre-install-$(date +%Y%m%d-%H%M%S)"

FILES=(CLAUDE.md .mcp.json settings.json statusline.sh)
DIRS=(rules skills hooks agents bin commands memory-global)

say() { printf '%s\n' "$*"; }
run() { [ "$DRY" -eq 1 ] && { say "would: $*"; return 0; }; "$@"; }

link() {
  local rel="$1" src="$REPO/$1" dst="$DEST/$1"
  [ -e "$src" ] || { say "skip $rel (not in repo)"; return; }
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then say "ok   $rel"; return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then run mkdir -p "$BACKUP"; run mv "$dst" "$BACKUP/"; fi
  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
  say "link $rel"
}

unlink_ours() {
  local rel="$1" dst="$DEST/$1"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$REPO/$1" ]; then
    run rm "$dst"; say "unlink $rel"
  else
    say "skip $rel (not our symlink)"
  fi
}

if [ "$MODE" = uninstall ]; then
  for f in "${FILES[@]}"; do unlink_ours "$f"; done
  for d in "${DIRS[@]}";  do unlink_ours "$d"; done
  say "done. your memory under $DEST and ~/.local/state/claude-memory was NOT removed."
  exit 0
fi

run mkdir -p "$DEST"
for f in "${FILES[@]}"; do link "$f"; done
for d in "${DIRS[@]}";  do link "$d"; done

# Executable bits (chmod follows symlinks, so target the repo directly).
# *.test.sh files are invoked via `sh <file>` (scripts/test-all.sh), never
# executed directly, so skip them — chmod'ing them here just dirties the
# tree against their tracked mode on every install.
if [ "$DRY" -eq 0 ]; then
  chmod +x "$REPO/statusline.sh" 2>/dev/null || true
  for f in "$REPO"/hooks/*.sh "$REPO"/hooks/lib/*.sh "$REPO"/scripts/*.sh; do
    case "$f" in *.test.sh) continue ;; esac
    chmod +x "$f" 2>/dev/null || true
  done
  for f in "$REPO"/bin/*; do
    case "$f" in *.test.sh) continue ;; esac
    chmod +x "$f" 2>/dev/null || true
  done
fi

# deep-think ships only as a Claude Code plugin now (no more PATH binary).
# Install it via the CLI if available; both subcommands are idempotent so
# re-running is safe once the marketplace/plugin already exist.
if [ "$DRY" -eq 1 ]; then
  say "would: install deep-think plugin (marketplace add + plugin install) if claude CLI is on PATH"
elif command -v claude >/dev/null 2>&1; then
  claude plugin marketplace add bis-code/claude-plugins >/dev/null 2>&1 || true
  claude plugin install deep-think@bis-code >/dev/null 2>&1 || true
  say "ok   deep-think plugin (marketplace + install)"
else
  say "skip deep-think plugin install (claude CLI not on PATH)"
fi

# Machine-local seeds — created only if absent, never overwritten.
if [ ! -e "$REPO/rules/about-me.local.md" ] && [ -f "$REPO/rules/about-me.example.md" ]; then
  run cp "$REPO/rules/about-me.example.md" "$REPO/rules/about-me.local.md"
  say "seed rules/about-me.local.md (gitignored — edit it)"
fi

# Capture-store layout (outside the repo; machine-local).
if [ "$DRY" -eq 0 ] && [ -f "$REPO/hooks/lib/memory-store.sh" ]; then
  sh -c '. "'"$REPO"'/hooks/lib/memory-store.sh"; memstore_init' || true
fi

# Optional: build the memory search index if leann is installed.
# GLOBAL_MEM_INDEX lets callers (tests, alternate setups) redirect the index
# name instead of touching the default claude-memory-global index.
if [ "$DRY" -eq 0 ] && command -v leann >/dev/null 2>&1; then
  sh "$REPO/hooks/memory-index-freshness.sh" "${GLOBAL_MEM_INDEX:-claude-memory-global}" "$DEST/memory-global" || true
else
  say "note: leann not found — semantic memory recall is disabled (everything else works)"
fi

[ -d "$BACKUP" ] && say "backups saved to: $BACKUP"
say "done. run ./bin/claude-setup-doctor, then start a new Claude Code session."
