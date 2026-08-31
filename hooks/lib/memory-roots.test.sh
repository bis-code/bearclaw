#!/bin/sh
# Tests for hooks/lib/memory-roots.sh — the single definition of where memory
# lives. Four callers depend on it agreeing with itself (recall hook,
# SessionStart, Stop, bin/claude-memory-recall); a tier indexed under one name
# and searched under another is a silent miss, not an error.
set +e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$DIR/memory-roots.sh"
PASS=0; FAIL=0

ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
no()  { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3], got [$2]"; }
has() { printf '%s' "$2" | grep -q "$3" && ok "$1" || no "$1" "missing /$3/ in: $2"; }
hasnt() { printf '%s' "$2" | grep -q "$3" && no "$1" "unexpected /$3/ in: $2" || ok "$1"; }

TMP=$(mktemp -d)

# ---- only roots that EXIST are emitted -----------------------------------
EMPTY_REPO="$TMP/empty-repo"; mkdir -p "$EMPTY_REPO"
OUT=$(GLOBAL_MEM_DIR="$TMP/nope" GLOBAL_MEM_INDEX=t-global memroots_emit "$EMPTY_REPO")
eq "no roots emitted when none exist" "$(printf '%s' "$OUT" | grep -c .)" "0"

# ---- global root honours its overrides ------------------------------------
GDIR="$TMP/gmem"; mkdir -p "$GDIR"
OUT=$(GLOBAL_MEM_DIR="$GDIR" GLOBAL_MEM_INDEX=t-global memroots_emit "$EMPTY_REPO")
has "global root emitted with its override name" "$OUT" "^t-global	$GDIR\$"

# ---- repo root: emitted, and named <basename>-memory ---------------------
REPO_A="$TMP/alpha"; mkdir -p "$REPO_A/.claude/memory"
OUT=$(GLOBAL_MEM_DIR="$GDIR" GLOBAL_MEM_INDEX=t-global memroots_emit "$REPO_A")
has "repo root emitted as <basename>-memory" "$OUT" "^alpha-memory	$REPO_A/.claude/memory\$"
eq "both roots present together" "$(printf '%s' "$OUT" | grep -c .)" "2"

# ---- no cross-repo bleed -------------------------------------------------
REPO_B="$TMP/beta"; mkdir -p "$REPO_B/.claude/memory"
OUT_B=$(GLOBAL_MEM_DIR="$GDIR" GLOBAL_MEM_INDEX=t-global memroots_emit "$REPO_B")
hasnt "repo B does not see repo A's tier" "$OUT_B" "alpha-memory"
has   "repo B gets its own tier" "$OUT_B" "beta-memory"

# ---- the harness's own per-project store is NOT a tier here -------------
# Deliberate: ~/.claude/projects/<encoded-cwd>/memory/ is Claude Code's own
# machine-local store, and whether to retrieve from it is the installer's
# decision, not this file's. The directory is CREATED here, under the name the
# harness itself would use (every character outside [A-Za-z0-9-] becomes "-"),
# so the assertion is about a store that genuinely exists and is genuinely
# skipped — not about an absent directory.
CFG_FAKE="$TMP/cfg"
NREPO="$TMP/native-repo"; mkdir -p "$NREPO/.claude/memory"
NENC=$(printf '%s' "$NREPO" | tr -c 'A-Za-z0-9-' '-')
mkdir -p "$CFG_FAKE/projects/$NENC/memory"
printf 'a note only the harness store holds\n' > "$CFG_FAKE/projects/$NENC/memory/n.md"
OUT_N=$(CLAUDE_CONFIG_DIR="$CFG_FAKE" GLOBAL_MEM_DIR="$GDIR" GLOBAL_MEM_INDEX=t-global \
        memroots_emit "$NREPO")
hasnt "the harness's own project store is not emitted as a tier" "$OUT_N" "native-repo-native"
eq "only the two documented roots are emitted" "$(printf '%s' "$OUT_N" | grep -c .)" "2"

# ---- a linked worktree resolves to the MAIN worktree --------------------
# Memory lives in the main checkout, so every worktree must share one index
# rather than each looking for a directory that is not in it.
GITREPO="$TMP/gitrepo"
mkdir -p "$GITREPO/.claude/memory"
( cd "$GITREPO" && git init -q . && git config user.email t@t && git config user.name t \
  && printf 'x\n' > f.txt && git add f.txt && git commit -qm init ) >/dev/null 2>&1
WT="$TMP/gitrepo-wt"
( cd "$GITREPO" && git worktree add -q -b wtbranch "$WT" ) >/dev/null 2>&1
if [ -d "$WT" ]; then
  OUT_WT=$(GLOBAL_MEM_DIR="$GDIR" GLOBAL_MEM_INDEX=t-global memroots_emit "$WT")
  # Matched on the tier name and the trailing path only: git reports the main
  # worktree through its resolved path, and on some platforms a temp dir is
  # reached through a symlink, so the absolute prefix legitimately differs
  # from $GITREPO.
  has "worktree resolves to the main checkout's memory" "$OUT_WT" "^gitrepo-memory	.*/gitrepo/.claude/memory\$"
  hasnt "worktree does not name itself as the tier" "$OUT_WT" "gitrepo-wt-memory"
else
  echo "SKIP: git worktree add failed; cannot check main-worktree resolution"
fi

rm -rf "$TMP"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
