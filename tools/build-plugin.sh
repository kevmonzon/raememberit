#!/usr/bin/env bash
# Regenerate the whole plugin/ tree from the sources of record.
#
# ONE SOURCE, TWO SHAPES. raememberit ships two ways — a settings fragment the standalone installer
# merges, and a plugin that carries its own hooks and code. They must say the same thing. Generating
# the plugin from the engine is the only way to guarantee that; this project has been bitten three
# times by two descriptions of one mechanism drifting apart. tools/test-plugin.sh asserts the
# committed tree matches what this script produces, so CI fails if someone edits one and not the other.
#
# THE ONE DISTINCTION THAT MATTERS: code is relocated, the corpus is not.
#   code   -> ${CLAUDE_PLUGIN_ROOT}/engine/...   (managed, replaced on every update)
#   corpus -> ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory   (resolved at runtime by lib/raememberit-root.sh)
# Nothing here rewrites a corpus path, and nothing may: a plugin directory is replaced on update and
# cannot hold a growing corpus.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- 1. the engine, verbatim ------------------------------------------------------------------
# No edits en route. Every engine script finds its siblings with $(dirname "$0"), so the same bytes
# work at the plugin root as at the config-dir path — which is exactly why no rewriting is needed.
rm -rf plugin/engine
cp -R engine plugin/engine
# The settings fragment is the standalone wiring; a plugin user never merges it, so it is not shipped.
rm -f plugin/engine/settings.fragment.json

# --- 1b. what setup needs in order to run: the installer and what it seeds from ----------------
# install.sh resolves its own directory as the source, so placing it at the plugin root next to
# engine/, starter/ and scaffold/ makes `--plugin` work unchanged. ONE installer, both routes — the
# alternative was a second implementation of corpus seeding, which is a drift surface by construction.
rm -rf plugin/starter plugin/scaffold
cp -R starter plugin/starter
cp -R scaffold plugin/scaffold
cp install.sh plugin/install.sh
chmod +x plugin/install.sh 2>/dev/null || true

# --- 1c. commands ------------------------------------------------------------------------------
# The standalone installer RENDERS the templates at install time. A plugin cannot: its files are
# managed and replaced on update. But the slots need no install-time knowledge —
#   {{MEM}}  is a shell assignment, so it resolves at RUNTIME from the environment
#   {{USER}} is prose, and the addressee now arrives via the hook's injected context (see
#            engine/hooks/inject-memory.sh), so the command text does not need a name baked in
rm -rf plugin/commands
mkdir -p plugin/commands
python3 - <<'PYCMD'
import glob, os, re

MEM_RUNTIME = 'MEM="${RAEMEMBERIT_MEMORY_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/memory}"   # resolved at runtime, not baked in'

for src in sorted(glob.glob("protocol/*.md.tmpl")):
    name = os.path.basename(src)[: -len(".md.tmpl")] + ".md"
    t = open(src).read()
    t = re.sub(r'MEM="\{\{MEM\}\}".*', MEM_RUNTIME, t)
    t = t.replace("{{USER}}", "the user")
    if "{{" in t:
        raise SystemExit("unfilled slot left in " + name + " — refusing to ship it")
    open(os.path.join("plugin/commands", name), "w").write(t)

# setup is plugin-only: a plugin user never runs a shell script, so for them the installer IS a command.
open("plugin/commands/setup.md", "w").write(open("protocol/setup.md").read())
PYCMD

# --- 2. hooks.json, with code paths repointed and the shim hook prepended ---------------------
python3 - <<'PY'
import json

frag = json.load(open("engine/settings.fragment.json"))
OLD = "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/raememberit/engine/"
NEW = "${CLAUDE_PLUGIN_ROOT}/engine/"

hooks = json.loads(json.dumps(frag["hooks"]))
for groups in hooks.values():
    for g in groups:
        for h in g["hooks"]:
            if not h["command"].startswith(OLD):
                raise SystemExit("unexpected command prefix, refusing to guess: " + h["command"])
            h["command"] = NEW + h["command"][len(OLD):]

# place-shim runs FIRST on SessionStart: the permission rule's target must exist before any command
# in the session tries to use it.
shim = {"type": "command", "command": NEW + "hooks/place-shim.sh", "timeout": 5}
ss = hooks.setdefault("SessionStart", [])
if ss and ss[0].get("matcher", "") == "":
    ss[0]["hooks"].insert(0, shim)
else:
    ss.insert(0, {"matcher": "", "hooks": [shim]})

out = {
    "description": (
        "raememberit's hooks. GENERATED from engine/settings.fragment.json by tools/build-plugin.sh "
        "- do not hand-edit. Code paths are ${CLAUDE_PLUGIN_ROOT}-relative; the corpus is resolved at "
        "runtime to the config dir by engine/lib/raememberit-root.sh and is never rewritten here."
    ),
    "hooks": hooks,
}
with open("plugin/hooks/hooks.json", "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")
PY

# --- 3. the manifest, with every knob declared as a typed option -------------------------------
python3 - <<'PY'
import json

manifest = {
    "name": "raememberit",
    "version": "0.2.0",
    "description": (
        "Memory discipline for Claude Code: a two-tier context budget, indexes generated from "
        "frontmatter, and hooks that make capture involuntary."
    ),
    "author": {"name": "raememberit"},
    # WHY userConfig AT ALL: it replaces the installer's template substitution. The standalone path
    # renders {{USER}} and {{MEM}} into command files at install time and needs a manifest plus
    # overwrite protection so a re-install cannot clobber an edit. Options are read at RUNTIME, so
    # there is nothing to render, nothing to clobber and nothing to protect.
    #
    # Each becomes CLAUDE_PLUGIN_OPTION_<NAME> in the environment of every hook and command.
    "userConfig": {
        "user": {
            "type": "string",
            "title": "How to address you",
            "description": "How the assistant should address you in its own memory files. Left empty, memories read impersonally.",
            "default": "",
        },
        "memoryDir": {
            "type": "string",
            "title": "Corpus location",
            "description": "Corpus location. Keep it inside the config directory so the whole directory stays one portable unit.",
            "default": "",
        },
        "dupes": {
            "type": "string",
            "title": "Duplicate gate",
            "description": "Duplicate gate on write. 'block' refuses a near-duplicate, 'warn' writes it and says so, 'off' skips the check. Start on 'warn' when adopting an existing corpus.",
            "options": ["block", "warn", "off"],
            "default": "warn",
        },
        "requireLog": {
            "type": "string",
            "title": "Require an interaction log",
            "description": "Whether a session may end without an interaction log. 'strict' refuses, 'warn' reminds, 'off' says nothing.",
            "options": ["warn", "strict", "off"],
            "default": "warn",
        },
        "precompactMessage": {
            "type": "string",
            "title": "Pre-compaction reminder",
            "description": "What the pre-compaction reminder says. Empty uses the default wording.",
            "default": "",
        },
        "recentN": {
            "type": "string",
            "title": "Recent logs in the index",
            "description": "How many recent interaction logs the always-on index lists. The always-on tier has no natural ceiling, so this is the knob that bounds it.",
            "default": "8",
        },
        "personaFile": {
            "type": "string",
            "title": "Persona file",
            "description": "Optional path to a persona file appended to the instruction fragment.",
            "default": "",
        },
        "vocabularyFile": {
            "type": "string",
            "title": "Vocabulary file",
            "description": "Optional path to a project-vocabulary file used when expanding recall queries.",
            "default": "",
        },
    },
}
with open("plugin/.claude-plugin/plugin.json", "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

echo "built plugin/ from engine/ + engine/settings.fragment.json"
echo "  plugin/engine/                $(find plugin/engine -type f | wc -l | tr -d ' ') files"
echo "  plugin/hooks/hooks.json       $(python3 -c 'import json;print(sum(len(g["hooks"]) for a in json.load(open("plugin/hooks/hooks.json"))["hooks"].values() for g in a))') hook entries"
echo "  plugin/commands/              $(find plugin/commands -name '*.md' | wc -l | tr -d ' ') commands"
echo "  plugin/.claude-plugin/        $(python3 -c 'import json;print(len(json.load(open("plugin/.claude-plugin/plugin.json"))["userConfig"]))') declared options"
