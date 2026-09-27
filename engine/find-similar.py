#!/usr/bin/env python3
"""Find existing memories that may already cover a new fact. Stdlib only.

    engine/find-similar.py "term one" "term two" ...
    engine/find-similar.py --desc "the description you were about to write"

WHY THIS IS A SCRIPT AND NOT AN INSTRUCTION: the capture command used to tell the assistant, in
prose, to "check for an existing file first". That step has a measured failure rate — three
separate memories describing one identical environment fact were written inside a four-hour
window, by one person, because a prose step is treated as advisory. A command you must run and
whose output you must answer to is much harder to skip than a paragraph you must remember.

Prints ranked candidates. Exit 0 always: this informs a verdict, it does not make one.
"""
import argparse, difflib, os, pathlib, re, sys

CONFIG = pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR") or (pathlib.Path.home()/".claude"))
MEM    = pathlib.Path(os.environ.get("MEMKIT_MEMORY_DIR") or (CONFIG/"memory"))
DIRS   = ["feedback", "project", "reference"]

def load():
    out = []
    for d in DIRS:
        for f in sorted((MEM/d).glob("*.md")):
            t = f.read_text(errors="replace")
            m = re.search(r"^description:\s*(.+)$", t, re.M)
            out.append({"path": f, "dir": d, "desc": (m.group(1).strip() if m else ""), "body": t})
    return out

def norm(s): return re.sub(r"[^a-z0-9 ]", " ", s.lower())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("terms", nargs="*", help="key nouns of the new fact")
    ap.add_argument("--desc", default="", help="the description you were about to write")
    ap.add_argument("--threshold", type=float, default=0.45)
    a = ap.parse_args()
    if not a.terms and not a.desc:
        ap.error("give some terms, or --desc")

    docs = load()
    if not docs:
        print(f"corpus at {MEM} holds no durable memories yet — nothing to collide with.")
        return 0

    scored = []
    for d in docs:
        hits = [t for t in a.terms if norm(t) in norm(d["body"])]
        dhits = [t for t in a.terms if norm(t) in norm(d["desc"])]
        sim = difflib.SequenceMatcher(None, norm(a.desc), norm(d["desc"])).ratio() if a.desc else 0.0
        # description matches and description similarity dominate: a memory whose DESCRIPTION
        # covers the fact is the one that will be retrieved instead of your new file.
        score = 2.0*len(dhits) + 1.0*len(hits) + 3.0*sim
        # A single body-term match is noise: in a corpus of a few hundred memories almost
        # everything shares one common noun. Require a DESCRIPTION hit, real description
        # similarity, or at least two distinct body terms before calling something a candidate.
        if len(dhits) >= 1 or sim >= 0.25 or len(hits) >= 2:
            scored.append((score, sim, len(hits), len(dhits), d))
    scored.sort(key=lambda r: -r[0])

    if not scored:
        print(f"no candidate overlap across {len(docs)} memories — ADD is defensible.")
        return 0

    print(f"{len(scored)} possible overlap(s) across {len(docs)} memories. "
          f"Read the files, then record a verdict per candidate.\n")
    for score, sim, nh, nd, d in scored[:8]:
        rel = d["path"].relative_to(MEM)
        flag = "  <-- LIKELY DUPLICATE" if sim >= a.threshold or nd >= 2 else ""
        print(f"  [{score:5.2f}] {rel}{flag}")
        print(f"          desc-sim {sim:.2f} · desc-terms {nd} · body-terms {nh}")
        if d["desc"]:
            print(f"          {d['desc'][:120]}")
    print("\nVerdicts: NOOP (already covered) · UPDATE (edit that file) · "
          "ADD (genuinely new) · SUPERSEDE (existing one is wrong).")
    print("Default to UPDATE. Two memories may coexist only if they answer DIFFERENT questions;")
    print("\"it is about a different ticket\" is not a different question.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
