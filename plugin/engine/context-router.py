#!/usr/bin/env python3
"""Prompt-time context router: surface prior memory and applicable skills for THIS prompt.

Invoked by hooks/context-router.sh on UserPromptSubmit with the hook's JSON on stdin. Stdlib only.

WHY THIS EXISTS. Capture in this kit is enforced by a script. Retrieval was a paragraph: "run /recall
before investigating anything cold". A paragraph is advisory, and the failure it produces is the one a
user notices most — being asked something they answered last week. This moves the first sweep into a
process that runs on every prompt, deterministically, with no model call:

  - MEMORIES  tokens from the prompt (and the working directory's name, and any ticket key) are scored
              against every catalog line and the domain index; the best few are named, with paths.
  - SKILLS    the same tokens against every installed command's and skill's `description:`; the best
              few are named as candidates. Descriptions are already in the model's system prompt — the
              value here is the targeted nudge at the moment the prompt arrives, not the listing.

TWO MODES PER FEATURE, AND SHADOW IS THE DEFAULT. `shadow` logs what it WOULD have surfaced and injects
nothing; `inject` adds it to the prompt's context; `off` does nothing. Shadow first, on purpose: a
hook that injects before its precision is measured is the always-on tier growing by another door.
Read .recall-log and .skill-log for a week, then flip.

  RAEMEMBERIT_AUTORECALL         shadow | inject | off   (default shadow)
  RAEMEMBERIT_SKILLROUTER        shadow | inject | off   (default shadow)
  RAEMEMBERIT_AUTORECALL_BUDGET  bytes the injected memory block may occupy (default 1500)
  RAEMEMBERIT_ROUTER_MAX         entries per block (default 3)

ONCE PER SESSION PER HIT. A path or skill already surfaced in this session is not surfaced again, so a
long session about one topic does not repeat itself every turn. The guard is a file keyed on the
session id, like inject-memory's.

COST: one python start plus a read of the catalog and the skill index — tens of milliseconds against a
5s timeout. The skill index is rebuilt only when a command or skill file is newer than it.
"""
import json, os, pathlib, re, sys, time

MEM = pathlib.Path(os.environ["RAEMEMBERIT_MEM"])
CONFIG = pathlib.Path(os.environ.get("RAEMEMBERIT_CONFIG") or os.environ.get("CLAUDE_CONFIG_DIR") or (pathlib.Path.home() / ".claude"))
TMP = pathlib.Path(os.environ.get("TMPDIR") or "/tmp")
MODE_MEM = os.environ.get("RAEMEMBERIT_AUTORECALL", "shadow").strip() or "shadow"
MODE_SK = os.environ.get("RAEMEMBERIT_SKILLROUTER", "shadow").strip() or "shadow"
BUDGET = int(os.environ.get("RAEMEMBERIT_AUTORECALL_BUDGET") or 1500)
MAXN = int(os.environ.get("RAEMEMBERIT_ROUTER_MAX") or 3)

# Words that carry no routing signal. Ordinary function words, plus the handful of engineering nouns so
# common in both prompts and memories that they match everything ("error", "test", "fix").
STOP = set("""
a about above after again all also always an and any are around as at back be because been before being
below between both but by can could did do does doing done down during each else even every few for
from further get give got had has have having he her here hers him his how i if in into is it its just
know let lets like look make may me might more most much must my need never new no nor not now of off ok
okay old on once only or other our ours out over own put right same say says see she should show so some
still such sure take tell than that the their theirs them then there these they thing things this those
through to too under until up us use used uses using very want was way we well were what when where
which while who whom why will with without would yes yet you your yours
also please thanks thank could would should really something anything everything nothing
code file files line lines change changes changed check checks fix fixes fixed issue issues problem
problems error errors bug bugs test tests testing run runs running work works working update updates
updated help make makes made want wants wanted need needs needed think thinks thought try tries tried
call calls called found find finds using used add adds added remove removes removed
claude user assistant session prompt memory memories skill skills command commands
""".split())

TICKET = re.compile(r"\b[A-Z][A-Z0-9]{1,9}-\d{1,6}\b")
WORD = re.compile(r"[a-z0-9][a-z0-9.+_-]{2,}")


def tokens(text):
    out = set()
    for w in WORD.findall(text.lower()):
        w = w.strip(".-_+")
        if len(w) < 4 or w in STOP or w.isdigit():
            continue
        out.add(w)
        # a hyphenated name also contributes its parts, so "billing-api" matches "billing"
        for part in re.split(r"[-_.]", w):
            if len(part) >= 4 and part not in STOP and not part.isdigit():
                out.add(part)
    return out


def load_catalog():
    """Every `- [name](path) — description` line of the on-demand catalog, plus its domains."""
    cat = MEM / "MEMORY-CATALOG.md"
    if not cat.exists():
        return []
    domains = {}
    dom = MEM / ".domain-index"
    if dom.exists():
        for line in dom.read_text(errors="replace").splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                domains.setdefault(parts[1], set()).add(parts[0].lower())
    entries = []
    for line in cat.read_text(errors="replace").splitlines():
        m = re.match(r"^- \[([^\]]+)\]\(([^)]+)\) — (.*)$", line)
        if not m:
            continue
        name, path, desc = m.group(1), m.group(2), m.group(3)
        desc = re.sub(r" · domain: .*$", "", desc)
        entries.append({"name": name, "path": path, "desc": desc,
                        "domains": domains.get(path, set()),
                        "toks": tokens(name + " " + desc), "text": (name + " " + desc)})
    return entries


def frontmatter(path):
    try:
        t = path.read_text(errors="replace")
    except OSError:
        return "", ""
    name = re.search(r"^name:\s*(.+)$", t, re.M)
    desc = re.search(r"^description:\s*(.+)$", t, re.M)
    return (name.group(1).strip().strip('"') if name else ""), (desc.group(1).strip().strip('"') if desc else "")


def skill_sources():
    """Every command and skill file that actually exists.

    A skills directory can hold a DANGLING SYMLINK — a skill that was moved or uninstalled while its
    link stayed — and glob() returns it while stat() raises. Measured on the first real machine this
    ran on: the router crashed on `skills/<name>/SKILL.md` pointing nowhere, on every prompt. A hook
    must never break a prompt, so anything that cannot be stat'ed is simply not a source.
    """
    out = []
    for f in sorted((CONFIG / "commands").glob("*.md")):
        if f.is_file():
            out.append(("command", f))
    for f in sorted((CONFIG / "skills").glob("*/SKILL.md")):
        if f.is_file():
            out.append(("skill", f))
    return out


def load_skills():
    """The skill index, rebuilt when any command or skill file is newer than it."""
    idx = MEM / ".skill-index"
    srcs = skill_sources()
    newest = max((f.stat().st_mtime for _, f in srcs), default=0)
    if not idx.exists() or idx.stat().st_mtime < newest or not srcs:
        rows = []
        for kind, f in srcs:
            name, desc = frontmatter(f)
            if not name:
                name = f.parent.name if kind == "skill" else f.stem
            rows.append("\t".join([name, kind, str(f), desc.replace("\t", " ")]))
        tmp = idx.with_suffix(".tmp")
        tmp.write_text("\n".join(rows) + ("\n" if rows else ""))
        tmp.replace(idx)
    out = []
    for line in idx.read_text(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        name, kind, path, desc = parts[0], parts[1], parts[2], parts[3]
        out.append({"name": name, "kind": kind, "path": path, "desc": desc,
                    "toks": tokens(name + " " + desc)})
    return out


def score_memories(entries, ptoks, keys, cwd_toks):
    scored = []
    for e in entries:
        hits = e["toks"] & ptoks
        s = len(hits)
        if any(k in e["text"] for k in keys):
            s += 5
        if e["domains"] & (ptoks | cwd_toks):
            s += 3
        # Two distinct content words, or one hard identifier (ticket key, domain). One shared noun
        # in a corpus of hundreds is noise — find-similar.py learned the same lesson.
        if s >= 2 and (len(hits) >= 2 or s >= 3):
            scored.append((s, e))
    scored.sort(key=lambda t: (-t[0], t[1]["name"]))
    return scored


def score_skills(skills, ptoks):
    scored = []
    for sk in skills:
        hits = sk["toks"] & ptoks
        if len(hits) >= 2:
            scored.append((len(hits), sk))
    scored.sort(key=lambda t: (-t[0], t[1]["name"]))
    return scored


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    prompt = (data.get("prompt") or "").strip()
    sid = re.sub(r"[^A-Za-z0-9-]", "", data.get("session_id") or "") or "nosid"
    cwd = data.get("cwd") or ""
    # A slash command is a decision already taken; a tiny prompt carries nothing to route on.
    if not prompt or prompt.startswith("/") or len(prompt) < 12:
        return 0
    ptoks = tokens(prompt)
    keys = set(TICKET.findall(prompt))
    cwd_toks = tokens(os.path.basename(cwd.rstrip("/"))) if cwd else set()
    if not ptoks and not keys and not cwd_toks:
        return 0

    guard = TMP / f"raememberit-surfaced-{sid}"
    seen = set(guard.read_text().split("\n")) if guard.exists() else set()
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    query = " ".join(sorted(ptoks | keys))[:200]
    blocks, newly = [], []

    if MODE_MEM != "off":
        chosen, used = [], 0
        for s, e in score_memories(load_catalog(), ptoks, keys, cwd_toks):
            if e["path"] in seen or len(chosen) >= MAXN:
                continue
            line = f"- {e['name']} — {e['desc']} ({e['path']})"
            if used + len(line) + 1 > BUDGET:
                break
            chosen.append(line); used += len(line) + 1; newly.append(e["path"])
        if chosen:
            with open(MEM / ".recall-log", "a") as f:
                f.write(f"{stamp}\tauto-{MODE_MEM}\t{sid}\t{query}\t{','.join(p for p in newly)}\n")
            if MODE_MEM == "inject":
                blocks.append("raememberit — prior memory that may apply to this prompt. Read the file "
                              "before relying on it; a memory records what was true when written:\n"
                              + "\n".join(chosen))

    if MODE_SK != "off":
        chosen_sk, new_sk = [], []
        for s, sk in score_skills(load_skills(), ptoks):
            if sk["name"] in seen or len(chosen_sk) >= MAXN:
                continue
            chosen_sk.append(f"- /{sk['name']} — {sk['desc'][:160]}"); new_sk.append(sk["name"])
        if chosen_sk:
            with open(MEM / ".skill-log", "a") as f:
                f.write(f"{stamp}\tauto-{MODE_SK}\t{sid}\t{query}\t{','.join(new_sk)}\n")
            newly.extend(new_sk)
            if MODE_SK == "inject":
                blocks.append("Installed skills whose description matches this prompt — invoke one if it "
                              "fits, rather than re-deriving its workflow:\n" + "\n".join(chosen_sk))

    if newly:
        with open(guard, "a") as f:
            f.write("\n".join(newly) + "\n")
    if blocks:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                                 "additionalContext": "\n\n".join(blocks)}}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # a hook must never break a prompt; say why on stderr and exit clean
        print(f"raememberit context-router: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(0)
