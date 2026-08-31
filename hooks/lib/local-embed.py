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
at ${XDG_STATE_HOME:-$HOME/.local/state}/claude-memory/local-embed-index.json.

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
CHUNK_MAX_CHARS = 800
CHUNK_MIN_CHARS = 120
SNIPPET_CHARS = 200


def index_path():
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "claude-memory", "local-embed-index.json")


_FRONTMATTER_RE = re.compile(r"\A---\n.*?\n---\n*", re.S)


def strip_frontmatter(text):
    """Drop a leading YAML frontmatter block — noise for embedding/snippets;
    memory-recall.py strips it too when the FULL body is available, but our
    ~200-char snippet is often too short to reach the closing '---' itself."""
    return _FRONTMATTER_RE.sub("", text, count=1)


def chunk_text(text):
    """Simple splitter: by `## ` heading if 2+ present, else the whole file
    as one section; each section windowed to ~CHUNK_MAX_CHARS by whole lines
    (never mid-line) so a long file still yields several embeddable chunks."""
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
        lines = section.splitlines()
        cur = []
        cur_len = 0
        for line in lines:
            if cur and cur_len + len(line) + 1 > CHUNK_MAX_CHARS:
                chunks.append("\n".join(cur).strip())
                cur = []
                cur_len = 0
            cur.append(line)
            cur_len += len(line) + 1
        if cur:
            chunks.append("\n".join(cur).strip())
    chunks = [c for c in chunks if c]

    # A trailing sliver (e.g. a lone "Related: [[...]]" line left over after a
    # window flush) embeds as a short, keyword-dense outlier that can outscore
    # the real match on cosine similarity — fold it into the previous chunk
    # instead of shipping it standalone.
    merged = []
    for c in chunks:
        if merged and len(c) < CHUNK_MIN_CHARS:
            merged[-1] = merged[-1] + "\n" + c
        else:
            merged.append(c)
    return merged


def load_corpus(corpus_dir):
    files = []
    for name in sorted(os.listdir(corpus_dir)):
        if not name.endswith(".md"):
            continue
        if name == "README.md":
            continue
        files.append(os.path.join(corpus_dir, name))
    return files


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
    records = []  # (path, chunk_text)
    for path in files:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except Exception:
            continue
        text = strip_frontmatter(text)
        for c in chunk_text(text):
            records.append((path, c))

    if not records:
        sys.stderr.write("local-embed: no chunks found under %s\n" % corpus_dir)
        return 1

    model = TextEmbedding(MODEL_NAME)
    vectors = list(model.embed([c for _, c in records]))

    out = {
        "model": MODEL_NAME,
        "corpus": os.path.abspath(corpus_dir),
        "chunks": [
            {"path": p, "chunk_text": c, "vector": [float(x) for x in v]}
            for (p, c), v in zip(records, vectors)
        ],
    }
    idx_path = index_path()
    os.makedirs(os.path.dirname(idx_path), exist_ok=True)
    tmp_path = idx_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    os.replace(tmp_path, idx_path)

    elapsed = time.time() - t0
    print("built %d chunks from %d files in %.2fs -> %s" % (len(records), len(files), elapsed, idx_path))
    return 0


def _cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(x * x for x in b) ** 0.5
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def cmd_search(args):
    idx_path = index_path()
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

    model = TextEmbedding(index.get("model", MODEL_NAME))
    qvec = list(model.embed([args.query]))[0]

    scored = []
    for c in chunks:
        score = _cosine(qvec, c["vector"])
        scored.append((score, c))
    scored.sort(key=lambda t: t[0], reverse=True)

    for score, c in scored[: args.top_k]:
        snippet = c["chunk_text"][:SNIPPET_CHARS]
        line = json.dumps({"score": round(float(score), 4), "path": c["path"], "snippet": snippet})
        sys.stdout.write(line + "\n")
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

    p_search = sub.add_parser("search")
    p_search.add_argument("query")
    p_search.add_argument("--top-k", type=int, default=5)

    args = ap.parse_args()
    if args.cmd == "build":
        return cmd_build(args)
    if args.cmd == "search":
        return cmd_search(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
