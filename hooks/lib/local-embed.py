#!/usr/bin/env python3
"""local-embed.py — fastembed-backed index/search for the local-embed memory
backend (hooks/lib/membackend-local-embed.sh, T15).

Replaces cognee (measured ~100s/query, disqualified) and leann (retired) for
live per-prompt curated-memory recall: a small fastembed index over
memory-global/*.md, sub-second, local, no service.

Run with the memory venv's python (install.sh creates it, guarded):
    <memory-venv>/bin/python3 local-embed.py build [--corpus DIR]
    <memory-venv>/bin/python3 local-embed.py search <query> [--top-k N]

Index file (JSON): {"model": "...", "chunks": [{"path", "chunk_text", "vector"}, ...]}
at ${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory/local-embed-<key>.json,
one file per corpus (--index-key; default "global").

Exit codes (contract shared with the membackend-local-embed.sh wrapper):
  0 = success (build: printed count+time; search: JSONL on stdout)
  3 = no backend / can't serve (missing index at search time, or fastembed
      itself unavailable) — caller falls back, never hangs or errors the hook
  1 = real error (bad args, corpus dir missing at build time)
"""
import argparse
import json
import os
import re
import sys
import time

MODEL_NAME = "BAAI/bge-small-en-v1.5"
# bge-* retrieval models are trained asymmetrically: passages are embedded bare,
# queries are embedded behind this instruction. Omitting it on the query side
# leaves query and passage vectors in slightly different spaces and costs recall
# for free. Query side ONLY — prefixing the stored passages too would undo it,
# and the existing index stays valid because passage vectors do not change.
QUERY_PREFIX = "Represent this sentence for searching relevant passages: "
CHUNK_MAX_CHARS = 800
CHUNK_MIN_CHARS = 120
SNIPPET_CHARS = 200


def model_cache_dir():
    """Where fastembed keeps the downloaded model (~64MB).

    fastembed defaults to $TMPDIR/fastembed_cache. On macOS that directory is
    periodically purged, so the first recall after a purge would re-download the
    model INSIDE the UserPromptSubmit hook — a multi-second stall on a path that
    is supposed to answer in under two seconds. Pin it somewhere durable and
    XDG-respecting instead. Override with MEMORY_MODEL_CACHE.
    """
    override = os.environ.get("MEMORY_MODEL_CACHE")
    if override:
        return override
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(
        os.path.expanduser("~"), ".cache"
    )
    return os.path.join(base, "claude-memory", "fastembed")


DEFAULT_INDEX_KEY = "global"

_KEY_SAFE_RE = re.compile(r"[^A-Za-z0-9._-]+")


def sanitize_key(key):
    """Reduce an index key to something safe to put in a filename.

    Keys arrive from callers as corpus NAMES ("claude-memory-global",
    "my-project-memory"), and a name is not automatically a path component: a
    key holding "/" or ".." would write the index outside the state dir.
    """
    key = _KEY_SAFE_RE.sub("-", (key or "").strip()).strip("-.")
    return key or DEFAULT_INDEX_KEY


def index_path(key=DEFAULT_INDEX_KEY):
    """Per-tier index file.

    One file per corpus, because the tiers are searched independently: a single
    shared file means whichever tier built last silently replaces the other's
    vectors, and a search then answers from the wrong corpus while looking
    perfectly healthy.
    """
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "claude-memory", "local-embed-%s.json" % sanitize_key(key))


_FRONTMATTER_RE = re.compile(r"\A---\n.*?\n---\n*", re.S)

# Retires one `## ` section from the index. Bold-markdown so it is visible to a
# reader of the file, not a hidden directive.
#
# The date is part of the marker in practice — "**Superseded 2026-08-31:**" — so
# anything between the word and the colon is allowed. Requiring the bare
# "**Superseded:**" is how the first version of this silently retired nothing:
# every marker actually written carried a date, and the test used the bare form,
# so the test passed while a stale entry went on scoring 0.85 in live recall.
_SUPERSEDED_RE = re.compile(r"(?m)^\*\*Superseded\b[^*\n]*:\*\*")


def strip_frontmatter(text):
    """Drop a leading YAML frontmatter block — noise for embedding/snippets;
    memory-recall.py strips it too when the FULL body is available, but our
    ~200-char snippet is often too short to reach the closing '---' itself."""
    return _FRONTMATTER_RE.sub("", text, count=1)


def chunk_text(text):
    """Split into (entry, chunk) pairs.

    Sections are cut at `## ` headings when 2+ are present, else the file is one
    section; each section is windowed to ~CHUNK_MAX_CHARS on line boundaries.

    `entry` is the section's heading, and it is the reason this returns pairs
    rather than strings. ERRORS.md alone holds ~54 dated entries and windows out
    to ~157 chunks that all share one path, so path is not an identity: nothing
    downstream could tell "another window of the entry we already picked" from
    "a different entry", and one grab-bag file could fill every top-k slot while
    genuinely relevant files went uninjected. Carrying the heading gives each
    entry a name to be deduplicated by. A section only keeps its heading in its
    FIRST window, which is exactly why the heading has to be recorded here
    instead of recovered from the chunk text later."""
    heading_starts = [m.start() for m in re.finditer(r"(?m)^##\s+.*$", text)]
    if len(heading_starts) >= 2:
        bounds = heading_starts + [len(text)]
        sections = [text[bounds[i]:bounds[i + 1]] for i in range(len(heading_starts))]
        if heading_starts[0] > 0:
            pre = text[:heading_starts[0]]
            if pre.strip():
                sections.insert(0, pre)
    else:
        sections = [text]

    chunks = []
    for section in sections:
        # A section carrying a **Superseded:** marker is not indexed at all.
        # `status: superseded` in frontmatter retires a whole FILE, which cannot
        # reach inside a grab-bag: ERRORS.md is one file with one slug holding
        # ~54 dated entries, so retiring a single stale entry there had no
        # mechanism short of splitting the file — and four consumers depend on it
        # staying one file. The marker keeps the entry readable by a person, with
        # its reasoning and its correction intact, while removing it from recall.
        if _SUPERSEDED_RE.search(section):
            continue
        m = re.match(r"(?m)\A##\s+(.*)$", section)
        entry = m.group(1).strip() if m else ""
        lines = section.splitlines()
        cur = []
        cur_len = 0
        for line in lines:
            if cur and cur_len + len(line) + 1 > CHUNK_MAX_CHARS:
                chunks.append((entry, "\n".join(cur).strip()))
                cur = []
                cur_len = 0
            cur.append(line)
            cur_len += len(line) + 1
        if cur:
            chunks.append((entry, "\n".join(cur).strip()))
    chunks = [(e, c) for (e, c) in chunks if c]

    # A trailing sliver (e.g. a lone "Related: [[...]]" line left over after a
    # window flush) embeds as a short, keyword-dense outlier that can outscore
    # the real match on cosine similarity — fold it into the previous chunk
    # instead of shipping it standalone.
    merged = []
    for entry, c in chunks:
        # Fold a sliver into the previous chunk only when it belongs to the SAME
        # entry. Merging across entries fuses two unrelated facts into one chunk
        # carrying the earlier one's name — so a short entry stops being
        # separately retrievable, and whatever is retrieved is mislabelled. The
        # sliver rule exists to stop a leftover "Related: [[...]]" line from
        # embedding as a keyword-dense outlier, and that leftover is always part
        # of the entry above it; a new heading is never a sliver of the last one.
        if merged and len(c) < CHUNK_MIN_CHARS and merged[-1][0] == entry:
            merged[-1] = (merged[-1][0], merged[-1][1] + "\n" + c)
        else:
            merged.append((entry, c))
    return merged


# Files that are ABOUT the corpus rather than part of it. MEMORY.md is the
# index: one `- [Title](slug.md) — hook` line per entry. Those lines are dense
# with exactly the words a query uses, so they rank well and win slots — but a
# pointer cannot answer anything, and the entry it points at is the thing worth
# injecting. Measured: 11 of 118 injected slots across the eval suite went to
# MEMORY.md, and none of them could ever count as a hit.
CORPUS_SKIP = ("README.md", "MEMORY.md")


_FILE_SUPERSEDED_RE = re.compile(r"(?m)^status:\s*superseded")


def _is_superseded(path):
    """True when the file's FRONTMATTER retires it.

    memory-recall.py also drops these at rank time, which covers a corpus not yet
    rebuilt. Skipping them here as well is what keeps them from occupying a
    candidate slot in the first place: a retired entry that still scores well
    crowds out a live one before the formatter ever sees either.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            head = fh.read(2048)
    except Exception:
        return False
    if not head.startswith("---"):
        return False
    fm_end = head.find("\n---", 3)
    return bool(_FILE_SUPERSEDED_RE.search(head[:fm_end] if fm_end != -1 else ""))


def load_corpus(corpus_dir):
    files = []
    for name in sorted(os.listdir(corpus_dir)):
        if not name.endswith(".md"):
            continue
        if name in CORPUS_SKIP:
            continue
        path = os.path.join(corpus_dir, name)
        if _is_superseded(path):
            continue
        files.append(path)
    return files


def _write_index(idx_path, model_name, args, corpus_dir, chunks):
    """Write an index atomically. Shared so the empty and non-empty paths cannot
    drift into producing differently-shaped files."""
    out = {
        "model": model_name,
        "index_key": sanitize_key(getattr(args, "index_key", DEFAULT_INDEX_KEY)),
        "corpus": os.path.abspath(corpus_dir),
        "chunks": chunks,
    }
    os.makedirs(os.path.dirname(idx_path), exist_ok=True)
    tmp_path = idx_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    os.replace(tmp_path, idx_path)


def cmd_build(args):
    try:
        from fastembed import TextEmbedding
    except Exception as e:
        sys.stderr.write("local-embed: fastembed unavailable (%s)\n" % e)
        return 3

    corpus_dir = args.corpus
    if not os.path.isdir(corpus_dir):
        sys.stderr.write("local-embed: corpus dir not found: %s\n" % corpus_dir)
        return 1

    t0 = time.time()
    files = load_corpus(corpus_dir)
    records = []  # (path, entry, chunk_text)
    for path in files:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except Exception:
            continue
        text = strip_frontmatter(text)
        for entry, c in chunk_text(text):
            records.append((path, entry, c))

    idx_path = index_path(getattr(args, "index_key", DEFAULT_INDEX_KEY))

    # An empty corpus is a SUCCESSFUL build of nothing, not an error. Returning
    # non-zero here meant the freshness stamp was never written, so every
    # SessionStart rediscovered the same empty directory and rebuilt it forever.
    # The written index is deliberately a real file with zero chunks — health
    # reads inside and calls that unhealthy, so the tier falls back to an eager
    # load rather than going slim against a corpus that can answer nothing.
    if not records:
        _write_index(idx_path, MODEL_NAME, args, corpus_dir, [])
        print("built 0 chunks from %d files in %.2fs -> %s"
              % (len(files), time.time() - t0, idx_path))
        return 0

    # Reuse vectors for chunks whose text is unchanged. A rebuild is triggered by
    # ONE edited note, and re-embedding all 279 chunks to absorb it costs ~10s of
    # five-core CPU; the unchanged 278 already have correct vectors sitting in the
    # index. Keyed on chunk text alone, because that plus the model is all an
    # embedding depends on — so a moved or renamed file also costs nothing.
    cached = {}
    if os.path.isfile(idx_path):
        try:
            with open(idx_path, encoding="utf-8") as fh:
                prev = json.load(fh)
            # A different model produces vectors in a different space; mixing them
            # in one index would silently corrupt every comparison.
            if prev.get("model") == MODEL_NAME:
                for ch in prev.get("chunks") or []:
                    txt, vec = ch.get("chunk_text"), ch.get("vector")
                    if txt and vec:
                        cached[txt] = vec
        except Exception:
            cached = {}   # unreadable index: rebuild from scratch, don't fail

    misses = [c for _, _, c in records if c not in cached]
    if misses:
        model = TextEmbedding(MODEL_NAME, cache_dir=model_cache_dir())
        for txt, vec in zip(misses, model.embed(misses)):
            cached[txt] = [float(x) for x in vec]

    chunks = [
        {"path": p, "entry": e, "chunk_text": c, "vector": cached[c]}
        for (p, e, c) in records
    ]
    _write_index(idx_path, MODEL_NAME, args, corpus_dir, chunks)

    elapsed = time.time() - t0
    print("built %d chunks from %d files in %.2fs (%d embedded, %d reused) -> %s"
          % (len(records), len(files), elapsed,
             len(misses), len(records) - len(misses), idx_path))
    return 0


def _cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(x * x for x in b) ** 0.5
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def cmd_search(args):
    idx_path = index_path(getattr(args, "index_key", DEFAULT_INDEX_KEY))
    if not os.path.isfile(idx_path):
        sys.stderr.write("local-embed: no index at %s (run build first)\n" % idx_path)
        return 3

    try:
        from fastembed import TextEmbedding
    except Exception as e:
        sys.stderr.write("local-embed: fastembed unavailable (%s)\n" % e)
        return 3

    try:
        with open(idx_path, encoding="utf-8") as fh:
            index = json.load(fh)
        chunks = index.get("chunks") or []
    except Exception as e:
        sys.stderr.write("local-embed: index unreadable (%s)\n" % e)
        return 3

    if not chunks:
        sys.stderr.write("local-embed: index has no chunks\n")
        return 3

    # Refuse to answer from the wrong corpus. Without this, pointing a tier at a
    # renamed or moved memory directory returns confident results from whatever
    # the index happened to hold — a silent failure that looks like healthy
    # recall, which is worse than no recall at all.
    want_corpus = getattr(args, "corpus", None)
    if want_corpus:
        have = index.get("corpus") or ""
        if os.path.abspath(want_corpus) != os.path.abspath(have):
            sys.stderr.write(
                "local-embed: index %s holds corpus %s, not %s (rebuild)\n"
                % (idx_path, have or "<unset>", os.path.abspath(want_corpus))
            )
            return 3

    model = TextEmbedding(index.get("model", MODEL_NAME), cache_dir=model_cache_dir())
    # Only bge-family models use this instruction; anything else embeds bare.
    _q = args.query
    if str(index.get("model", MODEL_NAME)).lower().startswith("baai/bge"):
        _q = QUERY_PREFIX + _q
    qvec = list(model.embed([_q]))[0]

    scored = []
    for c in chunks:
        score = _cosine(qvec, c["vector"])
        scored.append((score, c))
    scored.sort(key=lambda t: t[0], reverse=True)

    # One slot per (file, entry). Without this, a multi-entry file competes with
    # itself: ERRORS.md windows out to ~157 chunks of one path, so several
    # top-scoring chunks can be the same entry — or different entries that the
    # consumer cannot tell apart, since they arrive under one filename. Either
    # way the slots are spent and genuinely relevant files never get injected.
    # Keeping the best chunk per entry is what makes fetching more candidates
    # worthwhile rather than just fetching more of the same file.
    # Indexes built before `entry` existed have no such field; they collapse to
    # one chunk per file, which is correct-but-coarse and a rebuild fixes it.
    deduped = []
    seen = set()
    for score, c in scored:
        key = (c.get("path", ""), c.get("entry", ""))
        if key in seen:
            continue
        seen.add(key)
        deduped.append((score, c))
    scored = deduped

    for score, c in scored[: args.top_k]:
        snippet = c["chunk_text"][:SNIPPET_CHARS]
        line = json.dumps({"score": round(float(score), 4), "path": c["path"], "snippet": snippet})
        sys.stdout.write(line + "\n")
    return 0


def cmd_health(args):
    """Is this tier's index usable? Cheap by design — no model load, no embed.

    Runs on the SessionStart path where the answer only gates slim-vs-eager
    loading, so it must cost milliseconds. Checks the three things that make an
    index answerable: it exists, it holds the corpus asked for, it is not empty.
    """
    idx_path = index_path(getattr(args, "index_key", DEFAULT_INDEX_KEY))
    if not os.path.isfile(idx_path):
        sys.stderr.write("local-embed: no index at %s\n" % idx_path)
        return 3
    try:
        with open(idx_path, encoding="utf-8") as fh:
            index = json.load(fh)
    except Exception as e:
        sys.stderr.write("local-embed: index unreadable (%s)\n" % e)
        return 3
    if not (index.get("chunks") or []):
        sys.stderr.write("local-embed: index %s has no chunks\n" % idx_path)
        return 3
    want_corpus = getattr(args, "corpus", None)
    if want_corpus:
        have = index.get("corpus") or ""
        if os.path.abspath(want_corpus) != os.path.abspath(have):
            sys.stderr.write(
                "local-embed: index %s holds corpus %s, not %s\n"
                % (idx_path, have or "<unset>", os.path.abspath(want_corpus))
            )
            return 3
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    # Default corpus matches every other memory tool's convention: the
    # INSTALLED global memory dir, not a repo-relative path (this script runs
    # from ~/.claude/hooks/lib after install, same as memory-backend.sh).
    default_corpus = os.path.join(
        os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude"),
        "memory-global",
    )
    p_build = sub.add_parser("build")
    p_build.add_argument("--corpus", default=default_corpus)
    p_build.add_argument("--index-key", default=DEFAULT_INDEX_KEY)

    p_search = sub.add_parser("search")
    p_search.add_argument("query")
    p_search.add_argument("--top-k", type=int, default=5)
    p_search.add_argument("--index-key", default=DEFAULT_INDEX_KEY)
    # Optional: when given, search refuses an index built from another corpus.
    p_search.add_argument("--corpus", default=None)

    p_health = sub.add_parser("health")
    p_health.add_argument("--index-key", default=DEFAULT_INDEX_KEY)
    p_health.add_argument("--corpus", default=None)

    args = ap.parse_args()
    if args.cmd == "build":
        return cmd_build(args)
    if args.cmd == "search":
        return cmd_search(args)
    if args.cmd == "health":
        return cmd_health(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
