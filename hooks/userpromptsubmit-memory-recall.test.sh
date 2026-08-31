#!/bin/sh
set -e
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
export MEMORY_SEARCH_CMD='printf "[{\"text\":\"lesson about deploys\",\"score\":0.9,\"metadata\":{\"source\":\"a.md\"}}]"'
# trivial -> empty
out=$(printf '{"prompt":"ok","cwd":"/tmp"}' | sh "$DIR/userpromptsubmit-memory-recall.sh")
[ -z "$out" ] || { echo "FAIL: trivial prompt should produce nothing"; exit 1; }
# substantive -> block injected
out=$(printf '{"prompt":"how do deploys work in this system","cwd":"/tmp"}' | sh "$DIR/userpromptsubmit-memory-recall.sh")
echo "$out" | grep -q 'memory-context' || { echo "FAIL: expected injection"; exit 1; }
echo "PASS"

# --- Phase 2: usage logging (fallback: no file_name → id used as slug) ---
TMP_US=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP_US/store"
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"deploys-1\",\"text\":\"lesson about deploys\",\"score\":0.9,\"metadata\":{\"source\":\"a.md\"}}]"'
out=$(printf '{"prompt":"how do deploys work in this system","cwd":"/tmp"}' | sh "$DIR/userpromptsubmit-memory-recall.sh")
echo "$out" | grep -q 'memory-context' || { echo "FAIL: expected injection"; exit 1; }
LOG="$TMP_US/store/_usage/recall-log.jsonl"
[ -f "$LOG" ] || { echo "FAIL: usage log not written"; exit 1; }
grep -q '"deploys-1"' "$LOG" || { echo "FAIL: surfaced id not logged"; exit 1; }
echo "PASS"

# --- Phase 2b: usage logging (slug path: file_name present, numeric id differs) ---
# When metadata.file_name="deploy-notes.md" and id="99", the log must contain
# the SLUG "deploy-notes", NOT the numeric "99" — so prune can join by stem.
TMP_US2=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP_US2/store"
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"99\",\"text\":\"slug-path deploy lesson\",\"score\":0.9,\"metadata\":{\"file_name\":\"deploy-notes.md\"}}]"'
out=$(printf '{"prompt":"how do deploys work in this system","cwd":"/tmp"}' | sh "$DIR/userpromptsubmit-memory-recall.sh")
echo "$out" | grep -q 'memory-context' || { echo "FAIL 2b: expected injection"; exit 1; }
LOG2="$TMP_US2/store/_usage/recall-log.jsonl"
[ -f "$LOG2" ] || { echo "FAIL 2b: usage log not written"; exit 1; }
grep -q '"deploy-notes"' "$LOG2" || { echo "FAIL 2b: slug 'deploy-notes' not logged (got numeric id instead)"; exit 1; }
grep '"99"' "$LOG2" && { echo "FAIL 2b: numeric id '99' leaked into log (should be slug)"; exit 1; }
echo "PASS"
rm -rf "$TMP_US" "$TMP_US2"

# --- Phase 3 (#12): chunk-2 hit resolves recall_verify from the repo entry file ---
# The search stub returns a chunk with NO frontmatter in its text; the flag lives
# only in the source entry under <cwd>/.claude/memory/. The caveat must still appear.
TMP_P3=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP_P3/store"
mkdir -p "$TMP_P3/repo/.claude/memory"
printf -- '---\nname: state-entry\nrecall_verify: true\n---\nfull entry body\n' \
  > "$TMP_P3/repo/.claude/memory/state-entry.md"
export MEMORY_SEARCH_CMD='printf "[{\"id\":\"7\",\"text\":\"detail chunk without frontmatter\",\"score\":0.9,\"metadata\":{\"file_name\":\"state-entry.md\"}}]"'
out=$(printf '{"prompt":"how do deploys work in this system","cwd":"%s"}' "$TMP_P3/repo" | sh "$DIR/userpromptsubmit-memory-recall.sh")
echo "$out" | grep -q 'verify before relying' || { echo "FAIL 3: chunk-2 caveat not resolved from entry file"; exit 1; }
echo "PASS"
rm -rf "$TMP_P3"

# --- an unbuilt tier must not write to stderr on every prompt ---------------
# Searching every root means a repo whose index has not been built yet gets a
# tier immediately, and the backend prints "no index at ... run build first"
# for it. On the hot path that is one diagnostic per prompt, per unbuilt tier,
# forever — and the prompt can do nothing with it. The hook must stay silent
# and fail open. MEMORY_SEARCH_CMD must be UNSET, not merely unassigned: the
# tests above export it, and the stub would replace the very dispatch whose
# stderr this is about. Without the unset this passes with the fix reverted,
# which is how it was first written and how it was caught.
#
# On a machine with no local-embed venv (CI) the adapter exits 3 before it can
# print anything, so this check is satisfied without exercising the path. It is
# a real check only where the backend is installed. That is a deliberate
# trade — the alternative is a fake backend that prints on cue, which would
# test the stub rather than the hook.
unset MEMORY_SEARCH_CMD
TMP_P5=$(mktemp -d)
export MEMORY_STORE_DIR="$TMP_P5/store"
mkdir -p "$TMP_P5/norepo/.claude/memory"
printf -- '- a note in a tier that has never been indexed\n' \
  > "$TMP_P5/norepo/.claude/memory/n.md"
err=$(printf '{"prompt":"how does the memory index get rebuilt","cwd":"%s"}' "$TMP_P5/norepo" \
      | MEMORY_BACKEND=local-embed sh "$DIR/userpromptsubmit-memory-recall.sh" 2>&1 >/dev/null)
[ -z "$err" ] || { echo "FAIL: hook wrote to stderr for an unbuilt tier: $err"; exit 1; }
echo "PASS"
rm -rf "$TMP_P5"
