#!/bin/sh
# bootstrap-deps.sh — one-command fresh-machine dependency bootstrap.
# Run BEFORE install.sh on a fresh machine: installs git jq curl gh node bats
# (apt or brew), uv (official installer), leann (CPU-only wheels on Linux —
# CUDA torch is ~10.6GB of dead weight for memory-index embedding, see
# memory-global/ERRORS.md 2026-08-16), and the claude CLI.
# Idempotent; re-run safe. --dry-run prints actions without executing.
set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ "$DRY" -eq 1 ]; then say "would: $*"; else say "+ $*"; "$@"; fi; }

OS=$(uname -s)
PM=""
if have brew; then PM=brew
elif have apt-get; then PM=apt
else say "WARN no brew/apt found — install git/jq/curl/gh/node manually"; fi

# --- package-manager tools -------------------------------------------------
PKGS=""
for t in git jq curl gh bats; do have "$t" || PKGS="$PKGS $t"; done
have node || { [ "$PM" = "apt" ] && PKGS="$PKGS nodejs" || PKGS="$PKGS node"; }
if [ -n "$PKGS" ] && [ -n "$PM" ]; then
  case "$PM" in
    apt)  run sudo apt-get update; run sudo apt-get install -y $PKGS ;;
    brew) run brew install $PKGS ;;
  esac
else
  say "ok   package tools present (git jq curl gh node bats)"
fi

# --- uv --------------------------------------------------------------------
if have uv; then say "ok   uv"
elif [ "$DRY" -eq 1 ]; then say "would: install uv (curl astral.sh/uv/install.sh | sh)"
else
  curl -LsSf https://astral.sh/uv/install.sh | sh
  PATH="$HOME/.local/bin:$PATH"; export PATH
fi

# --- leann (CPU-only wheels on Linux) --------------------------------------
if have leann; then
  say "ok   leann"
elif have uv || [ "$DRY" -eq 1 ]; then
  if [ "$OS" = "Linux" ]; then
    # --torch-backend=cpu if this uv supports it; else ranked CPU index.
    if uv tool install --help 2>/dev/null | grep -q torch-backend; then
      run uv tool install leann-core --python 3.13 \
        --with leann-backend-hnsw --with leann --torch-backend=cpu
    else
      run uv tool install leann-core --python 3.13 \
        --with leann-backend-hnsw --with leann \
        --index https://download.pytorch.org/whl/cpu --index-strategy unsafe-best-match
    fi
  else
    run uv tool install leann-core --python 3.13 --with leann-backend-hnsw --with leann
  fi
  # uv hardlinks its cache into the venv; nltk's CWE-59 guard refuses
  # multiply-linked data files — clean drops nlink to 1 (and frees ~5GB).
  run uv cache clean
else
  say "WARN leann skipped (uv unavailable)"
fi

# --- claude CLI ------------------------------------------------------------
if have claude; then
  say "ok   claude CLI ($(claude --version 2>/dev/null | awk '{print $1; exit}'))"
  run claude update
elif [ "$DRY" -eq 1 ]; then
  say "would: install claude CLI (curl claude.ai/install.sh | bash)"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

say "bootstrap done — next: ./install.sh, then bin/claude-setup-doctor"
