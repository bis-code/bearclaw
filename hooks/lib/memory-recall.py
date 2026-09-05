#!/usr/bin/env python3
import sys, os, json, argparse, re, time

def _score(r):
    """Safely coerce a result's score to float; returns 0.0 on any failure."""
    try:
        return float(r.get("score") or 0)
    except (TypeError, ValueError):
        return 0.0

def _load_usage(path):
    """Return {id: {"count": n, "last_ts": epoch}} from a JSONL usage log.
    Never raises — a missing/garbage log yields {}."""
    stats = {}
    if not path or not os.path.exists(path):
        return stats
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts = rec.get("ts") or 0
                try:
                    ts = float(ts)
                except (TypeError, ValueError):
                    ts = 0.0
                for rid in (rec.get("ids") or []):
                    s = stats.setdefault(rid, {"count": 0, "last_ts": 0.0})
                    s["count"] += 1
                    if ts > s["last_ts"]:
                        s["last_ts"] = ts
    except Exception:
        return {}
    return stats

# Ceiling on the usage boost. It is a TIEBREAKER, and the size is calibrated
# from real score distributions rather than chosen: among the top candidates for
# a live prompt, adjacent raw scores sit 2-3% apart while a clearly better match
# leads by ~7%. A 5% ceiling therefore separates entries the embedder cannot
# meaningfully distinguish, and cannot overturn one it can.
#
# It was 2.0x (+0.5 frequency, +0.5 recency), which is not a tiebreak — it is a
# veto. Measured on the live log before this changed: ERRORS sat at the 2.0x
# ceiling with 135 recalls, five more entries were pinned at >=1.9x, and a new
# memory at 1.0x needed a raw score twice as high to place. Cosine scores here
# live in 0.5-0.75, so twice as high is unreachable: once an entry was recalled
# often enough, nothing could displace it. The system had surfaced 17 distinct
# memories, ever, out of 44 — a rich-get-richer lock-in in which being recalled
# was the main qualification for being recalled again. It also defeats a newly
# indexed tier outright, since every entry in one starts cold.
USAGE_BOOST_MAX_FREQ = 0.025      # saturates at 10 recalls
USAGE_BOOST_MAX_RECENCY = 0.025   # full value today, gone after ~30 days


def _usage_boost(rid, stats, now):
    """Multiplier in [1.0, 1.05] from recall frequency + recency.

    Breaks ties between entries the scores cannot separate. Deliberately too
    small to promote a worse match over a better one — see the ceiling above.
    """
    s = stats.get(rid)
    if not s:
        return 1.0
    freq_factor = min(s.get("count", 0) * (USAGE_BOOST_MAX_FREQ / 10.0),
                      USAGE_BOOST_MAX_FREQ)
    age_days = max((now - s.get("last_ts", 0)) / 86400.0, 0)
    recency_factor = USAGE_BOOST_MAX_RECENCY * max(1.0 - age_days / 30.0, 0.0)
    return 1.0 + freq_factor + recency_factor

def _file_flags(slug, mem_dirs, cache={}):
    """Resolve recall_verify/pinned/superseded from the source entry's
    FRONTMATTER, so non-first chunks of a multi-chunk entry still carry their
    flags (#12). Never raises; missing file/dir → no flags."""
    if not slug or not mem_dirs:
        return {"verify": False, "pinned": False, "superseded": False}
    if slug in cache:
        return cache[slug]
    flags = {"verify": False, "pinned": False, "superseded": False}
    for d in mem_dirs:
        if not d:
            continue
        try:
            with open(os.path.join(d, slug + ".md"), encoding="utf-8", errors="replace") as fh:
                head = fh.read(2048)
        except Exception:
            continue
        if not head.startswith("---"):
            continue
        fm_end = head.find("\n---", 3)
        fm = head[:fm_end] if fm_end != -1 else ""
        if re.search(r"(?m)^recall_verify:\s*true", fm):
            flags["verify"] = True
        if re.search(r"(?m)^pinned:\s*true", fm):
            flags["pinned"] = True
        # A memory that has been superseded but not deleted. Retiring by
        # deletion loses the reasoning that made the old entry worth writing,
        # and a fact that turned out wrong is itself worth keeping — but it must
        # stop reaching prompts, because a confidently stated stale fact is
        # worse than no memory at all. Observed: a note describing a search
        # engine that had since been replaced kept being injected, carrying
        # score thresholds that were wrong for the engine that replaced it.
        if re.search(r"(?m)^status:\s*superseded", fm):
            flags["superseded"] = True
    cache[slug] = flags
    return flags

def main():
    try:
        ap = argparse.ArgumentParser()
        ap.add_argument("--floor", type=float, default=0.5)
        ap.add_argument("--top-k", type=int, default=3)
        ap.add_argument("--budget-tokens", type=int, default=400)
        ap.add_argument("--usage-log", default=os.environ.get("MEMORY_USAGE_LOG", ""))
        ap.add_argument("--mem-dir", action="append", default=[],
                        help="source memory dir(s) for per-file flag resolution (repeatable)")
        a = ap.parse_args()
        try:
            results = json.load(sys.stdin)
        except Exception:
            return  # never raise from a hook path
        if not isinstance(results, list):
            return  # non-array JSON — treat as no results

        # Floor filters on the RAW base score (a cold entry is never demoted out).
        kept = [r for r in results if _score(r) >= a.floor]
        if not kept:
            return

        stats = _load_usage(a.usage_log)
        now = time.time()

        def _slug(r):
            """Stable entry identity: stem of metadata.file_name, or fall back to chunk id."""
            try:
                fname = (r.get("metadata") or {}).get("file_name", "")
                if fname:
                    return os.path.splitext(os.path.basename(fname))[0]
            except Exception:
                pass
            return str(r.get("id", ""))

        # Superseded entries are dropped outright rather than demoted. A rank
        # penalty still lets one through on a quiet query, and "mostly retired"
        # is not a useful state for a fact that is simply no longer true.
        kept = [r for r in kept if not _file_flags(_slug(r), a.mem_dir)["superseded"]]
        if not kept:
            return

        def effective(r):
            base = _score(r)
            body = (r.get("text") or "")
            pinned = (re.search(r"(?m)^pinned:\s*true", body) is not None
                      or _file_flags(_slug(r), a.mem_dir)["pinned"])
            mult = 1.5 if pinned else 1.0
            return base * mult * _usage_boost(_slug(r), stats, now)

        kept.sort(key=effective, reverse=True)
        # A per-file slot cap would go here, between the sort and the slice.
        # Deliberately absent. On one live install ERRORS.md (~56% of the index
        # by chunk count) looked like it was crowding everything else out at
        # 84 organic recalls (32% of slots); at 948 recalls it held 17%, which
        # for a file that size is under-represented, not crowding — the early
        # figure was small-sample noise. Recalls where it took ALL slots stayed
        # at the same 5 across 864 further recalls: an artifact of a then-small
        # corpus. sessionstart-memory-tuning-nudge.sh watches the share and
        # speaks up only if it climbs back past its bar; add a cap then, with
        # the measurement, not before.
        kept = kept[: a.top_k]

        budget = a.budget_tokens
        lines = ["<memory-context>"]
        chosen_slugs = []
        for r in kept:
            if budget <= 0:
                break
            body = (r.get("text") or "").strip()
            verify = (re.search(r"(?m)^recall_verify:\s*true", body) is not None
                      or _file_flags(_slug(r), a.mem_dir)["verify"])
            body = re.sub(r"^---.*?---\s*", "", body, flags=re.S)        # strip frontmatter
            body = body.replace("</memory-context>", "<\\/memory-context>")  # escape
            max_chars = budget * 4
            if len(body) > max_chars:
                body = body[:max_chars] + "…"
            budget -= len(body) // 4
            prefix = "⚠ verify before relying — " if verify else ""
            lines.append(f"- {prefix}{body}")
            slug = _slug(r)
            if slug:
                chosen_slugs.append(slug)
        if len(lines) == 1:
            return
        lines.append("</memory-context>")
        sys.stdout.write("\n".join(lines) + "\n")

        # Emit chosen slugs on fd 3 for the recall hook's usage logger. fd 3 may not
        # be open (e.g. direct CLI use) — that's fine, swallow the error.
        if chosen_slugs:
            try:
                with os.fdopen(3, "w", closefd=False) as fh3:
                    fh3.write("\n".join(chosen_slugs) + "\n")
            except Exception:
                pass
    except Exception:
        return  # unconditional hook-safety net

if __name__ == "__main__":
    main()
