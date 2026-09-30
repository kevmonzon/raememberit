#!/usr/bin/env python3
"""Retrieval eval harness for a raememberit corpus.

Stdlib only, no deps, no daemon — it must survive the same `cp -r ~/.claude` the
corpus does.

  python3 engine/eval/run_eval.py              # both strategies + health
  python3 engine/eval/run_eval.py --strategy literal
  python3 engine/eval/run_eval.py --health
  python3 engine/eval/run_eval.py --json       # machine-readable

RANKING CAVEAT: /recall specifies no ranking — `grep -ril` returns filesystem order.
To compute hit@1 at all, this harness imputes the ranking the command's prose implies:
  1. frontmatter `description:` match beats body-only match
  2. more distinct query terms matched beats fewer
  3. newer mtime beats older ("prefer the newest hits")
Any candidate design that defines its own ranking should replace `search()` only.
"""
import argparse, json, os, pathlib, re, shutil, sys, time
from difflib import SequenceMatcher

# Root resolution mirrors engine/lib/raememberit-root.sh: CLAUDE_CONFIG_DIR relocates the whole
# config but does NOT change $HOME, so hardcoding ~/.claude would make an isolated run read
# the default corpus instead of the sandboxed one.
CONFIG = pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR") or (pathlib.Path.home()/".claude"))

# Mirror of engine/lib/raememberit-root.sh. The corpus lives INSIDE the config dir so the
# whole directory stays one portable unit; writes get there via engine/mem-write.sh over
# Bash, because the Edit/Write tools refuse paths inside `.claude` and an allow rule does
# not override that. Reads are not gated, so this reads directly.
MEM = pathlib.Path(os.environ.get("RAEMEMBERIT_MEMORY_DIR") or (CONFIG/"memory"))
DIRS   = ["feedback", "project", "reference"]
NATIVE = sorted((CONFIG/"projects").glob("*/memory"))
QUERIES = pathlib.Path(os.environ.get("RAEMEMBERIT_QUERIES") or (MEM/"eval/queries.json"))

def load_docs():
    docs = {}
    for d in DIRS:
        for f in sorted((MEM/d).glob("*.md")):
            t = f.read_text(errors="replace")
            m = re.search(r"^description:\s*(.+)$", t, re.M)
            key = f"{d}/{f.name}"
            desc = (m.group(1) if m else "").strip().strip('"')
            nm = re.search(r"^name:\s*(.+)$", t, re.M)
            docs[key] = {
                "path": f, "text": t,
                "name": (nm.group(1).strip() if nm else f.stem),
                # Faithful to /recall step 2: the catalog line is `- [name](path) — description`,
                # so name and path are searchable, not just body prose.
                "lower": (key + "\n" + f.stem.replace("-", " ") + "\n" + t).lower(),
                "desc": (f.stem.replace("-", " ") + " " + desc).lower(),
                "mtime": f.stat().st_mtime,
            }
    return docs

def load_native():
    """The native silo is cwd-KEYED, so the same filename recurs in every store.

    Keying this by `f.stem` silently collapsed them: four stores each hold a `MEMORY.md`, so three
    were overwritten and the reported corpus size was 14 where 17 files exist. A dict keyed by a
    non-unique field does not error — it drops, and reports the smaller number as fact. Key by the
    store as well, so a collision is impossible rather than merely unlikely.
    """
    out = {}
    for base in NATIVE:
        store = base.parent.name
        for f in sorted(base.glob("*.md")):
            out[f"{store}/{f.stem}"] = f.read_text(errors="replace").lower()
    return out

def native_text(native, stem):
    """Content of every native memory with this stem, across all cwd-keyed stores.

    Storage is keyed `store/stem` so nothing is silently overwritten, but queries address a memory
    by stem alone — they cannot know which working directory it was written from. Resolving here
    keeps both true: an honest count, and a lookup that does not care where the file lives.
    """
    hits = [v for k, v in native.items() if k.split("/", 1)[-1] == stem]
    return "\n".join(hits)


def _matcher(term):
    """Short terms must match on a word boundary.

    A bare substring search for a 2-char acronym matches inside hundreds of ordinary words
    ("CA" is in "because", "cannot") and buries the true hits. Measured: adding one such
    2-char variant pushed a genuinely relevant memory from rank 4 to rank 74. Longer terms
    stay plain substrings, so a tool name still matches a memory whose slug merely contains
    it.
    """
    t = term.lower()
    if len(t) <= 3:
        rx = re.compile(r"(?<![a-z0-9])" + re.escape(t) + r"(?![a-z0-9])")
        return lambda blob: bool(rx.search(blob))
    return lambda blob: t in blob

def search(docs, terms):
    """Imputed-rank retrieval over the markdown corpus. Case-insensitive."""
    ms = [(t, _matcher(t)) for t in terms]
    hits = []
    for key, d in docs.items():
        matched = {t for t, m in ms if m(d["lower"])}
        if not matched:
            continue
        desc_hit = any(m(d["desc"]) for _, m in ms)
        hits.append((key, desc_hit, len(matched), d["mtime"]))
    hits.sort(key=lambda h: (not h[1], -h[2], -h[3]))
    return [h[0] for h in hits]

def resolve_expect(want, docs):
    """Map one `expect` entry to a corpus key, or None when nothing on disk answers to it.

    An entry may be a key (`project/x.md`) or a bare `name:` (the example file uses those). An
    entry naming a file that no longer exists used to score as a retrieval MISS — the same line
    the harness prints when retrieval genuinely fails — so a renamed memory read as a ranking
    defect for eight days while the memory sat at rank 1. Missing is a different fact from
    unranked, and it gets its own word.
    """
    if want in docs:
        return want
    by_name = {d["name"]: k for k, d in docs.items()}
    if want in by_name:
        return by_name[want]
    stem = pathlib.PurePath(want).stem
    return by_name.get(stem)

def rename_hint(want, docs):
    """The most likely current key for an expectation that resolves to nothing.

    Renames in this corpus keep the topic and drop or add a prefix (a date, a ticket key), so a
    key whose stem ends the expected stem, or the reverse, is the candidate worth naming. A hint,
    not a resolution: the expectation is still reported missing, because silently following a
    guess would turn the guard back into decoration.
    """
    stem = pathlib.PurePath(want).stem.lower()
    cands = [k for k, d in docs.items()
             if k != want and (stem.endswith(d["path"].stem.lower()) or d["path"].stem.lower().endswith(stem))]
    return min(cands, key=len) if cands else None

def evaluate(q, docs, native, strategy):
    # The shipped example file spells a query `{"q": ..., "expect": [...]}` and nothing else; the
    # full form adds id, category, variants and mode. Accept the short form, with `any` as the
    # mode, so the example runs rather than raising KeyError on its first entry.
    q = {**q, "query": q.get("query", q.get("q"))}
    q.setdefault("id", q["query"]); q.setdefault("category", "-"); q.setdefault("mode", "any")
    terms = [q["query"]] if strategy == "literal" else q.get("variants", [q["query"]])
    mode  = q["mode"]
    r = {"id": q["id"], "category": q["category"], "mode": mode, "strategy": strategy}

    if mode == "native":
        want = q.get("expect_native", [])
        # Reachability is EXISTENCE here, not term-matching: the original expression ended in
        # `or n in native`, which made the term test unreachable whenever the memory was present.
        # Said plainly rather than left as dead code inside a condition.
        found = [n for n in want if native_text(native, n)]
        r.update(passed=len(found) == len(want), detail=f"{len(found)}/{len(want)} native memories reachable")
        return r

    results = search(docs, terms)
    r["n_results"] = len(results)

    if mode == "none":
        r.update(passed=len(results) == 0,
                 detail="clean" if not results else f"FALSE POSITIVES: {results[:3]}")
        return r

    resolved = {w: resolve_expect(w, docs) for w in q["expect"]}
    missing  = [w for w, k in resolved.items() if k is None]
    want     = [k for k in resolved.values() if k]
    if missing:
        r["expect_missing"] = missing
        notes = []
        for w in missing:
            h = rename_hint(w, docs)
            notes.append(f"{w}" + (f" (renamed? now {h})" if h else ""))
        r["missing_note"] = "EXPECT-MISSING: " + "; ".join(notes)
    if not want:
        r.update(passed=False, detail=r["missing_note"])
        return r
    if mode == "exactly_one":
        present = [w for w in want if w in results]
        r.update(passed=len(present) == 1,
                 detail=f"{len(present)} of {len(want)} near-identical memories retrievable (want exactly 1)")
        return _noted(r)

    ranks = {w: (results.index(w) + 1 if w in results else None) for w in want}
    got   = [w for w, k in ranks.items() if k]
    if mode == "all":
        k = len(want) + 2
        inwin = [w for w, rk in ranks.items() if rk and rk <= k]
        r.update(passed=len(inwin) == len(want),
                 detail=f"{len(inwin)}/{len(want)} within top-{k}; ranks={sorted(v for v in ranks.values() if v)}")
        return _noted(r)

    best = min((v for v in ranks.values() if v), default=None)
    r.update(hit1=best == 1, hit3=bool(best and best <= 3), passed=bool(best and best <= 3),
             detail=f"best rank {best}" if best else f"MISS (0/{len(want)} retrieved)")
    if q.get("path_claim"):
        p = pathlib.Path(os.path.expanduser(q["path_claim"]))
        tool = q.get("requires_tool")
        if tool and shutil.which(tool) is None:
            # The path belongs to a tool this machine does not have. Absent is the expected
            # state, not evidence the memory rotted: the health section already draws the same
            # line for repos that are not checked out here. Unverifiable is the honest word.
            r["path_claim_exists"] = None
            r["detail"] += f"; claimed path UNVERIFIABLE ({tool} not installed): {q['path_claim']}"
        else:
            r["path_claim_exists"] = p.exists()
            r["detail"] += f"; claimed path {'EXISTS' if p.exists() else 'GONE'}: {q['path_claim']}"
    if q.get("scope_warning") and got:
        r["detail"] += f"; SCOPE-LIMITED ({q['scope_warning']}) — must be labelled when reported"
    return _noted(r)

def _noted(r):
    """A missing expectation is reported on every mode's line, not only the rank-based one.

    `exactly_one` and `all` count the expectations that resolved; one that did not resolve would
    otherwise drop out of the denominator and the line would read as a smaller, cleaner test.
    """
    if r.get("missing_note"):
        if r["missing_note"] not in r["detail"]:
            r["detail"] += "; " + r["missing_note"]
        # The members that DID resolve may all rank — the test still failed, because the file
        # it was written to guard is not there. Caught by the suite on first run: `all` went
        # green with one member missing, since the missing one had left the denominator.
        r["passed"] = False
    return r

def health(docs):
    names, links, paths_ok, paths_bad = {}, [], 0, []
    for key, d in docs.items():
        m = re.search(r"^name:\s*(.+)$", d["text"], re.M)
        if m: names[m.group(1).strip()] = key
    # ARCHIVED memories are valid LINK TARGETS even though they are not SCORED. They sit outside
    # DIRS on purpose — finished work should not be marked for retrieval quality — but a `[[slug]]`
    # pointing at one resolves perfectly well through the catalog. Omitting them here reported every
    # such link as dangling: moving four memories to archive/ invented five phantom findings.
    for f in (MEM/"archive").glob("*.md"):
        m = re.search(r"^name:\s*(.+)$", f.read_text(errors="replace"), re.M)
        names.setdefault((m.group(1).strip() if m else f.stem), f"archive/{f.stem}")
    linked_to = set()
    for key, d in docs.items():
        for l in re.findall(r"\[\[([^\]]+)\]\]", d["text"]):
            links.append((key, l.strip()))
            if l.strip() in names: linked_to.add(names[l.strip()])
    dangling = [(s, l) for s, l in links if l not in names]
    orphans  = [k for k in docs if k not in linked_to]
    placeholders = skipped_repo = 0
    for key, d in docs.items():
        for raw in re.findall(r"`(~/[^`\s]+|/Users/[^`\s]+)`", d["text"]):
            raw = raw.rstrip('.,;:')
            # A path containing <angle brackets> is a documentation TEMPLATE, not a claim.
            # Counting these as broken inflated the failure rate badly on 2026-09-21.
            if "<" in raw or ">" in raw:
                placeholders += 1
                continue
            p = pathlib.Path(os.path.expanduser(raw))
            if p.exists():
                paths_ok += 1
                continue
            # This corpus is portable and has crossed machines (native silos carry Windows
            # paths). A claim about a repo that was never cloned here is unverifiable, not
            # stale — do not score it either way.
            m = re.match(r"^~/code/([^/]+)", raw)
            if m and not pathlib.Path(os.path.expanduser(f"~/code/{m.group(1)}")).exists():
                skipped_repo += 1
                continue
            paths_bad.append((key, raw))
    dups = []
    keys = list(docs)
    for i in range(len(keys)):
        for j in range(i+1, len(keys)):
            a, b = docs[keys[i]]["desc"], docs[keys[j]]["desc"]
            if a and b and SequenceMatcher(None, a, b).ratio() > 0.65:
                dups.append((keys[i], keys[j]))
    total_paths = paths_ok + len(paths_bad)
    return {
        "memories": len(docs), "wikilinks": len(links),
        "dangling": len(dangling), "dangling_pct": round(100*len(dangling)/max(len(links),1),1),
        "orphans": len(orphans), "orphan_pct": round(100*len(orphans)/max(len(docs),1),1),
        "path_claims": total_paths, "path_ok": paths_ok,
        "path_ok_pct": round(100*paths_ok/max(total_paths,1),1),
        "path_placeholders_skipped": placeholders,
        "path_unverifiable_repo_absent": skipped_repo,
        "dup_pairs": len(dups),
        "_dangling": dangling[:10], "_dups": dups[:10], "_bad_paths": paths_bad[:10],
    }


def delivery(window_h=48):
    """Did the always-on index actually REACH the model?

    Every check above this one reads the corpus off disk, which is exactly the blind spot that let
    13 consecutive truncated sessions report green (measured 2026-09-28). Retrieval quality is
    worthless if the index never arrives, so this asserts the delivery path, not the content.

    No size threshold is hardcoded: the harness ceiling is undocumented and lives in a
    self-updating binary. Instead this counts the artifacts the harness itself writes when it
    declines to inject — the same evidence hooks/truncation-tripwire.sh uses.
    """
    idx = MEM / "MEMORY.md"
    size = idx.stat().st_size if idx.exists() else 0
    mark = re.compile(r"AUTO-GENERATED by .*rebuild-index\.sh")
    cutoff = time.time() - window_h * 3600
    hits, largest = [], 0
    proj = CONFIG / "projects"
    if proj.is_dir():
        for f in proj.glob("*/*/tool-results/hook-*-additionalContext.txt"):
            try:
                if f.stat().st_mtime < cutoff: continue
                if not mark.search(f.read_text(errors="replace")): continue
            except OSError:
                continue
            hits.append(f.name)
            largest = max(largest, f.stat().st_size)
    return {
        "always_on_bytes": size,
        "truncated_sessions": len(hits),
        "largest_truncated_payload": largest,
        "window_hours": window_h,
        "delivered": len(hits) == 0,
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strategy", choices=["literal", "expanded", "both"], default="both")
    ap.add_argument("--health", action="store_true", help="structural checks only")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict-dupes", action="store_true",
                    help="exit 1 if any near-duplicate description pair exists. Run this right "
                         "after writing a memory: it turns the corpus's most common defect from "
                         "something an audit finds months later into something the write itself "
                         "refuses to leave behind.")
    a = ap.parse_args()

    docs, native = load_docs(), load_native()
    out = {"corpus": len(docs), "native": len(native)}

    # --health is structural only: it must not require a query file. A fresh install has no
    # queries yet, and an empty corpus is exactly when health output is most wanted.
    spec = None
    if not a.health:
        if not QUERIES.exists():
            print(f"no query file at {QUERIES}\n"
                  f"  retrieval scoring needs one (see engine/eval/queries.example.json);\n"
                  f"  run with --health for structural checks that need no queries.",
                  file=sys.stderr)
            return 2
        spec = json.loads(QUERIES.read_text())

    if not a.health:
        strategies = ["literal", "expanded"] if a.strategy == "both" else [a.strategy]
        out["runs"] = {}
        for st in strategies:
            rs = [evaluate(q, docs, native, st) for q in spec["queries"]]
            out["runs"][st] = {
                "passed": sum(r["passed"] for r in rs), "total": len(rs),
                "hit1": sum(1 for r in rs if r.get("hit1")),
                "hit3": sum(1 for r in rs if r.get("hit3")),
                "results": rs,
            }
    out["health"] = health(docs)
    out["delivery"] = delivery()

    if a.strict_dupes:
        n = out["health"].get("dup_pairs", 0)          # count
        pairs = out["health"].get("_dups", [])          # the pairs themselves
        if n:
            print(f"STRICT-DUPES: {n} near-duplicate description pair(s):", file=sys.stderr)
            for pr in pairs:
                for f in pr:
                    print(f"  {f}", file=sys.stderr)
                print("  ---", file=sys.stderr)
            print("Merge or differentiate them. Two memories may coexist only if they answer\n"
                  "different questions; \"it is about a different ticket\" is not a different\n"
                  "question.", file=sys.stderr)
            return 1

    if a.json:
        print(json.dumps(out, indent=2, default=str)); return

    print(f"corpus: {out['corpus']} memories · native silo: {out['native']} files\n")
    for st, run in out.get("runs", {}).items():
        print(f"=== strategy: {st} — {run['passed']}/{run['total']} passed "
              f"(hit@1 {run['hit1']}, hit@3 {run['hit3']}) ===")
        for r in run["results"]:
            print(f"  {'PASS' if r['passed'] else 'FAIL'}  {r['id']:26} {r['category']:18} {r['detail']}")
        print()
    d = out["delivery"]
    print("=== delivery (does the index reach the model?) ===")
    print(f"  always-on     MEMORY.md is {d['always_on_bytes']} bytes")
    if d["delivered"]:
        print(f"  DELIVERED     no truncated injections in the last {d['window_hours']}h")
    else:
        print(f"  *** FAILED    {d['truncated_sessions']} session(s) in the last {d['window_hours']}h "
              f"had the index truncated to a file preview (largest payload "
              f"{d['largest_truncated_payload']} B).")
        print( "                Scores below describe a corpus the model never received.")
    print()
    h = out["health"]
    print("=== structural health ===")
    print(f"  wikilinks     {h['wikilinks']} total, {h['dangling']} dangling ({h['dangling_pct']}%)")
    print(f"  orphans       {h['orphans']}/{h['memories']} ({h['orphan_pct']}%) nothing links to them")
    print(f"  path claims   {h['path_ok']}/{h['path_claims']} verifiable claims exist ({h['path_ok_pct']}%)")
    print(f"                {h['path_placeholders_skipped']} <template> paths skipped (not claims), "
          f"{h['path_unverifiable_repo_absent']} unverifiable (repo absent on this machine)")
    print(f"  dup pairs     {h['dup_pairs']} description pairs >0.65 similar")
    if h["_dups"]:
        print("  near-duplicates:")
        for x, y in h["_dups"]: print(f"    - {x}\n      {y}")

if __name__ == "__main__":
    sys.exit(main() or 0)   # propagate the exit code; None -> 0
