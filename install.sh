#!/usr/bin/env bash
set -euo pipefail
# Copies this repo into ~/.claude/ (copy-on-install, not symlinks — Claude
# Code atomic-writes settings.json on /config etc., which replaced an old
# symlink with a real file and dropped repo-only keys). ~/.claude/.installed-from
# records which repo + commit produced the copy, for tools that need to find
# the repo (the drift/staleness hooks) now that readlink can't.
# Idempotent: safe to re-run after `git pull`. Backs up real files once.
#
# Usage:
#   ./install.sh [DEST]              install (DEST defaults to ~/.claude)
#   ./install.sh --dry-run [DEST]    print what would happen, change nothing
#
# This script touches ONLY $DEST and $XDG_STATE_HOME/claude-memory. It never
# modifies your global git config, your ~/.gitconfig, or your shell rc files.

DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1; shift ;;
    -h|--help)   sed -n '3,12p' "$0"; exit 0 ;;
    *)           break ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/.claude}"

# Safety guard for the directory copy_dir() below (which does an rm -rf of a
# known $DEST subpath before repopulating it): refuse outright if DEST itself
# resolves to something a wrong argument or a broken env could turn into "/",
# "$HOME", or empty — copy_dir would otherwise be one bad $rel away from
# wiping the wrong tree.
case "$DEST" in
  "") echo "ERROR: DEST resolved empty — refusing to install" >&2; exit 1 ;;
esac
DEST_REAL="$(CDPATH= cd -P "$(dirname "$DEST")" 2>/dev/null && pwd)/$(basename "$DEST")" || DEST_REAL="$DEST"
# Squeeze duplicate slashes and drop a trailing slash before comparing: with
# DEST="/", dirname and basename both return "/", so the naive join above
# produces the literal string "///" — which the "/" pattern below would NOT
# match without this normalization.
DEST_REAL="$(printf '%s' "$DEST_REAL" | sed -e 's#/\{2,\}#/#g' -e 's#\(.\)/$#\1#')"
case "$DEST_REAL" in
  "/"|"$HOME")
    echo "ERROR: refusing to install into $DEST (resolves to $DEST_REAL)" >&2
    exit 1 ;;
esac

BACKUP="$DEST/backups/pre-install-$(date +%Y%m%d-%H%M%S)"

FILES=(CLAUDE.md .mcp.json settings.json statusline.sh)
DIRS=(rules skills hooks agents bin commands memory-global)

say() { printf '%s\n' "$*"; }

# Preflight: report every external command the installed setup depends on,
# BEFORE touching anything. Hard requirements abort; everything else is
# informational so a skipped feature is a visible choice, not a surprise.
# Deliberately check-only — this script never installs other software
# (see the touches-only-$DEST guarantee above).
preflight() {
  local hard_missing=0
  say "-- preflight ------------------------------------------------------"
  # Hard requirements: hooks parse JSON with jq; the destructive-command
  # guard (hooks/guard-destructive.py) is python3; git is how everything
  # here versions and links.
  # No associative arrays — macOS ships bash 3.2.
  hint() {
    case "$1" in
      jq)      echo "brew install jq | apt-get install jq" ;;
      git)     echo "xcode-select --install | apt-get install git" ;;
      python3) echo "ships with macOS CLT | apt-get install python3 — WITHOUT it hooks/guard-destructive.py (the catastrophic-delete guard) cannot run" ;;
      claude)  echo "npm install -g @anthropic-ai/claude-code" ;;
      leann)   echo "uv tool install leann-core (or pipx)" ;;
      gh)      echo "brew install gh | apt-get install gh" ;;
      bats)    echo "brew install bats-core | apt-get install bats" ;;
      terminal-notifier) echo "brew install terminal-notifier (macOS nicety; osascript fallback used otherwise)" ;;
    esac
  }
  local c
  for c in jq git python3; do
    if command -v "$c" >/dev/null 2>&1; then say "ok   $c"
    else say "MISS $c  (REQUIRED — $(hint "$c"))"; hard_missing=1; fi
  done
  if command -v claude >/dev/null 2>&1; then say "ok   claude"
  else say "MISS claude  (this config is FOR Claude Code — $(hint claude); the deep-think plugin step will be skipped)"; fi
  for c in leann gh bats terminal-notifier; do
    if command -v "$c" >/dev/null 2>&1; then say "ok   $c"
    else say "note $c not found (optional — $(hint "$c"))"; fi
  done
  if [ "$hard_missing" -eq 1 ]; then
    say "-- preflight FAILED: install the required tools above, then re-run."
    exit 1
  fi
  say "-------------------------------------------------------------------"
}
run() { [ "$DRY" -eq 1 ] && { say "would: $*"; return 0; }; "$@"; }

# Files: cp, backing up whatever was at $dst (real file OR a leftover symlink
# from an old link-based install) the first time it differs from the repo.
copy_file() {
  local rel="$1"
  local src="$REPO/$rel"
  local dst="$DEST/$rel"

  [ -e "$src" ] || { say "skip $rel (not in repo)"; return; }

  if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst" 2>/dev/null; then
    say "ok   $rel"
    return
  fi

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    run mkdir -p "$BACKUP"
    run mv "$dst" "$BACKUP/"
  fi

  run mkdir -p "$(dirname "$dst")"
  run cp "$src" "$dst"
  say "copy $rel"
}

# Directories: copy contents (rsync -a --delete when available; cp -R after an
# rm -rf of $dst otherwise). $dst is always "$DEST/$rel" for one of the fixed
# names in DIRS above — never a wildcard — so the rm -rf can only ever remove
# a known entry under DEST, never DEST itself or anything above it.
copy_dir() {
  local rel="$1"
  local src="$REPO/$rel"
  local dst="$DEST/$rel"

  [ -e "$src" ] || { say "skip $rel (not in repo)"; return; }
  [ -n "$rel" ] || { echo "REFUSE copy_dir with empty rel" >&2; return 1; }
  case "$dst" in
    "$DEST"/*) : ;;
    *) echo "REFUSE copy_dir dst outside DEST: $dst" >&2; return 1 ;;
  esac

  if [ -L "$dst" ]; then
    run mkdir -p "$BACKUP"
    run mv "$dst" "$BACKUP/"
  fi

  run mkdir -p "$dst"
  # memory-global and skills legitimately accumulate content that never lived
  # in the repo: a memory promotion can land a freshly-promoted entry straight
  # into $DEST/memory-global before it's committed, and skills is where a
  # third-party installer (a plugin marketplace) writes from now on — that not
  # landing inside the tracked repo is the point of copy-on-install. --delete
  # would erase both on the very next install.sh run, so neither directory
  # prunes; only rules/hooks/agents/bin/commands mirror the repo exactly (a
  # file removed from the repo disappears from DEST too).
  case "$rel" in
    memory-global|skills)
      if command -v rsync >/dev/null 2>&1; then
        run rsync -a "$src/" "$dst/"
      else
        run cp -R "$src/." "$dst/"
      fi
      ;;
    rules)
      # rules/about-me.local.md is gitignored and DEST-only (seeded once,
      # below, and then hand-edited) — exclude it from the prune so a plain
      # --delete sync doesn't wipe it on every re-run.
      if command -v rsync >/dev/null 2>&1; then
        run rsync -a --delete --exclude=about-me.local.md "$src/" "$dst/"
      else
        # No rsync: skip the delete pass rather than risk rm -rf clobbering
        # about-me.local.md too — an overlay copy still keeps DEST current,
        # just without pruning files the repo has since removed.
        run cp -R "$src/." "$dst/"
      fi
      ;;
    *)
      if command -v rsync >/dev/null 2>&1; then
        run rsync -a --delete "$src/" "$dst/"
      else
        run rm -rf "$dst"
        run mkdir -p "$dst"
        run cp -R "$src/." "$dst/"
      fi
      ;;
  esac
  say "copy $rel"
}

preflight

run mkdir -p "$DEST"
for f in "${FILES[@]}"; do copy_file "$f"; done
# Whole-dir copies — anything dropped into rules/skills/hooks/agents/bin/commands
# lands on the next install.sh run (not live-immediately, unlike symlinks).
for d in "${DIRS[@]}";  do copy_dir "$d"; done

# Record what produced this copy — the drift/staleness hooks and a memory
# promotion need to find the repo now that readlink on ~/.claude/* can't.
INSTALL_SHA="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$DRY" -eq 1 ]; then
  say "would: write $DEST/.installed-from (repo=$REPO sha=$INSTALL_SHA)"
else
  printf 'repo=%s\nsha=%s\n' "$REPO" "$INSTALL_SHA" > "$DEST/.installed-from"
fi
say "ok   .installed-from (sha=$INSTALL_SHA)"

# Test seam: everything from here down is machine-wide side effects (plugin
# install, memory-index build) that a test must not trigger against the real
# machine. INSTALL_TEST_STOP_AFTER_COPY=1 stops right after the part under
# test — the copy + .installed-from — leaving install.sh itself as the thing
# exercised, not a reimplementation of it.
[ "${INSTALL_TEST_STOP_AFTER_COPY:-0}" = "1" ] && exit 0

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
  # ...and on the just-copied DEST tree — a real copy no longer inherits
  # chmod changes to the repo automatically the way a symlink did, so this
  # has to be asserted on both sides. rsync/cp preserve the source's mode
  # bits, but this makes it deterministic regardless of which copy path ran.
  chmod +x "$DEST/statusline.sh" 2>/dev/null || true
  for f in "$DEST"/hooks/*.sh "$DEST"/hooks/lib/*.sh "$DEST"/scripts/*.sh; do
    case "$f" in *.test.sh) continue ;; esac
    chmod +x "$f" 2>/dev/null || true
  done
  for f in "$DEST"/bin/*; do
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
if [ ! -e "$DEST/rules/about-me.local.md" ] && [ -f "$REPO/rules/about-me.example.md" ]; then
  run cp "$REPO/rules/about-me.example.md" "$DEST/rules/about-me.local.md"
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

# Optional: local-embed memory backend (a lighter alternative to the leann
# index above — a small fastembed index over memory-global/*.md, no service).
# memoryBackend defaults to "none" (plain file reads); set it to "local-embed"
# in settings.json to opt in once this venv is set up. Guarded on python3: a
# machine without it degrades to memoryBackend=none, same as any other
# missing-backend machine.
MEMORY_VENV="${MEMORY_VENV:-$DEST/memory-venv}"
if ! command -v python3 >/dev/null 2>&1; then
  say "skip memory venv (python3 not installed — local-embed backend degrades to none)"
elif [ "$DRY" -eq 1 ]; then
  say "would: set up memory venv + fastembed for the local-embed backend"
else
  if [ ! -x "$MEMORY_VENV/bin/python3" ]; then
    run python3 -m venv "$MEMORY_VENV"
  fi
  if "$MEMORY_VENV/bin/python3" -c 'import fastembed' >/dev/null 2>&1; then
    say "ok   memory venv (fastembed already installed)"
  elif "$MEMORY_VENV/bin/pip" install --quiet fastembed >/dev/null 2>&1; then
    say "ok   memory venv (fastembed installed)"
  else
    say "WARN memory venv fastembed install failed — local-embed backend degrades to none until fixed"
  fi
  if [ -x "$MEMORY_VENV/bin/python3" ] && "$MEMORY_VENV/bin/python3" -c 'import fastembed' >/dev/null 2>&1; then
    # Build under the corpus NAME the hooks search, not the builder's default
    # key. Indexes are one-file-per-corpus now, so a build under any other key
    # writes an index nothing ever reads — the recall gate then reports the
    # backend unhealthy and every session eager-loads instead, with no error
    # anywhere to explain it. Derived by the same function the hooks use, so
    # the two cannot drift.
    GLOBAL_IDX=$(CLAUDE_CONFIG_DIR="$DEST" sh -c '. "'"$REPO"'/hooks/lib/memory-roots.sh"; memroots_global_index')
    if MEMORY_VENV="$MEMORY_VENV" CLAUDE_CONFIG_DIR="$DEST" \
       sh "$REPO/hooks/lib/membackend-local-embed.sh" build "$GLOBAL_IDX" "$DEST/memory-global" >/dev/null 2>&1; then
      say "ok   local-embed index (memory-global -> $GLOBAL_IDX)"
    else
      say "WARN local-embed index build failed — recall falls back to none until fixed"
    fi
  fi
fi

[ -d "$BACKUP" ] && say "backups saved to: $BACKUP"
say "done. run ./bin/claude-setup-doctor, then start a new Claude Code session."
