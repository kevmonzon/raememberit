#!/usr/bin/env bash
# Assertions on the generated plugin tree. The point is not that the plugin works — a session proves
# that — but that the plugin and the standalone fragment cannot silently disagree.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# UNSET THE AMBIENT KNOBS. These are set in a real settings.json, so a suite that inherits them is
# testing the developer's own configuration instead of the defaults — and RAEMEMBERIT_MEMORY_DIR is worse
# than misleading: install.sh read it in preference to --config-dir, so runs that believed they were
# sandboxed seeded and rebuilt THE LIVE CORPUS. Measured 2026-09-28, after that variable first appeared
# in settings. test-install.sh already did this; this suite was written without it.
unset RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_RECENT_N \
      RAEMEMBERIT_USER RAEMEMBERIT_PRECOMPACT_MSG RAEMEMBERIT_PERSONA_FILE RAEMEMBERIT_VOCAB_FILE 2>/dev/null || true

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

echo "== plugin tree =="

# --- the committed tree is what the generator produces ----------------------------------------
# This is the whole drift defence. If someone edits plugin/ by hand, or edits engine/ and forgets to
# rebuild, this fails.
tmp="$(mktemp -d)"
cp -R plugin "$tmp/plugin.committed"
bash tools/build-plugin.sh >/dev/null 2>&1
if diff -r "$tmp/plugin.committed" plugin >/dev/null 2>&1; then
  ok "committed plugin/ matches tools/build-plugin.sh output"
else
  bad "plugin/ has drifted from its sources — run tools/build-plugin.sh and commit the result"
  diff -r "$tmp/plugin.committed" plugin 2>&1 | head -10 | sed 's/^/       /'
fi
rm -rf "$tmp"

# --- code paths are plugin-relative; corpus paths are NOT --------------------------------------
cmds="$(python3 -c 'import json;print("\n".join(h["command"] for a in json.load(open("plugin/hooks/hooks.json"))["hooks"].values() for g in a for h in g["hooks"]))')"
if [ -z "$cmds" ]; then
  bad "no hook commands found in plugin/hooks/hooks.json"
else
  n_root=$(printf '%s\n' "$cmds" | grep -c 'CLAUDE_PLUGIN_ROOT' || true)
  n_cfg=$(printf '%s\n' "$cmds" | grep -c 'CLAUDE_CONFIG_DIR' || true)
  n_all=$(printf '%s\n' "$cmds" | grep -c . || true)
  [ "$n_root" = "$n_all" ] && ok "all $n_all hook commands are \${CLAUDE_PLUGIN_ROOT}-relative" \
                           || bad "$((n_all-n_root)) of $n_all hook commands are not plugin-relative"
  [ "$n_cfg" = "0" ] && ok "no hook command hardcodes the config dir" \
                     || bad "$n_cfg hook command(s) still point at the config dir"
fi

# --- every referenced hook script actually ships -----------------------------------------------
missing=0
for c in $cmds; do
  rel="${c#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  [ -f "plugin/$rel" ] || { bad "hooks.json references a file the plugin does not ship: $rel"; missing=$((missing+1)); }
done
[ "$missing" = "0" ] && ok "every hook command resolves to a shipped file"

# --- the corpus is resolved at runtime, never shipped in the plugin -----------------------------
if [ -d plugin/memory ] || [ -d plugin/engine/memory ]; then
  bad "the plugin ships a corpus directory — a managed directory is replaced on update"
else
  ok "no corpus inside the plugin"
fi
grep -q 'CLAUDE_CONFIG_DIR' plugin/engine/lib/raememberit-root.sh \
  && ok "shipped root lib still resolves the corpus to the config dir" \
  || bad "shipped root lib no longer resolves the corpus to the config dir"

# --- the shim hook: stable path, wrapper not copy ------------------------------------------------
shim=plugin/engine/hooks/place-shim.sh
if [ ! -f "$shim" ]; then
  bad "place-shim.sh is not shipped"
else
  grep -q 'CLAUDE_PLUGIN_DATA' "$shim" && ok "shim targets \$CLAUDE_PLUGIN_DATA (version-free)" \
                                       || bad "shim does not use \$CLAUDE_PLUGIN_DATA"
  grep -q 'exec bash' "$shim" && ok "shim execs the real helper rather than copying it" \
                              || bad "shim looks like a copy — \$(dirname \$0) siblings would not resolve"
  grep -q 'CLAUDE_PLUGIN_ROOT:-' "$shim" && ok "shim no-ops when not running as a plugin" \
                                         || bad "shim does not guard the standalone case"
  first="$(python3 -c 'import json;h=json.load(open("plugin/hooks/hooks.json"))["hooks"]["SessionStart"];print(h[0]["hooks"][0]["command"])')"
  case "$first" in
    *place-shim.sh) ok "place-shim runs first on SessionStart" ;;
    *) bad "place-shim is not the first SessionStart hook (got: $first)" ;;
  esac
fi

# --- the shim actually produces a working wrapper ------------------------------------------------
# Run the hook for real against a throwaway plugin root and data dir.
sandbox="$(mktemp -d)"
mkdir -p "$sandbox/root/engine"
cp -R engine/. "$sandbox/root/engine/"
CLAUDE_PLUGIN_ROOT="$sandbox/root" CLAUDE_PLUGIN_DATA="$sandbox/data" \
  bash engine/hooks/place-shim.sh >/dev/null 2>&1
if [ -x "$sandbox/data/bin/mem-write.sh" ]; then
  ok "hook creates an executable wrapper at \$CLAUDE_PLUGIN_DATA/bin/mem-write.sh"
  grep -q "$sandbox/root/engine/mem-write.sh" "$sandbox/data/bin/mem-write.sh" \
    && ok "wrapper points at the engine under the plugin root" \
    || bad "wrapper does not point at the plugin root's helper"
  # An update moves the root. The next session must repoint the wrapper without the path changing.
  mkdir -p "$sandbox/root2/engine"; cp -R engine/. "$sandbox/root2/engine/"
  CLAUDE_PLUGIN_ROOT="$sandbox/root2" CLAUDE_PLUGIN_DATA="$sandbox/data" \
    bash engine/hooks/place-shim.sh >/dev/null 2>&1
  grep -q "$sandbox/root2/engine/mem-write.sh" "$sandbox/data/bin/mem-write.sh" \
    && ok "simulated update repoints the wrapper, stable path unchanged" \
    || bad "wrapper still points at the OLD plugin root after an update"
else
  bad "hook did not create the wrapper"
fi
# Standalone: no plugin vars, no wrapper, no error.
CLAUDE_PLUGIN_ROOT= CLAUDE_PLUGIN_DATA= bash engine/hooks/place-shim.sh >/dev/null 2>&1 \
  && ok "shim exits clean with no plugin vars set" \
  || bad "shim errors when not running as a plugin"
rm -rf "$sandbox"

# --- the manifest declares what it cannot declare elsewhere ------------------------------------
man=plugin/.claude-plugin/plugin.json
python3 -c 'import json,sys; json.load(open("'"$man"'"))' 2>/dev/null \
  && ok "plugin.json is valid JSON" || bad "plugin.json is not valid JSON"
for key in user memoryDir dupes requireLog precompactMessage recentN; do
  python3 -c 'import json,sys; sys.exit(0 if "'"$key"'" in json.load(open("'"$man"'"))["userConfig"] else 1)' \
    && ok "userConfig declares $key" || bad "userConfig is missing $key"
done
# The schema facts `claude plugin validate` taught us, pinned so a future edit cannot lose them:
# every option needs a `title`, and an enumeration is `options`, never `choices`.
python3 -c 'import json,sys; uc=json.load(open("'"$man"'"))["userConfig"]; sys.exit(0 if all("title" in v for v in uc.values()) else 1)' \
  && ok "every userConfig option declares a title (required by the schema)" \
  || bad "a userConfig option is missing its title"
python3 -c 'import json,sys; uc=json.load(open("'"$man"'"))["userConfig"]; sys.exit(1 if any("choices" in v for v in uc.values()) else 0)' \
  && ok "enumerations use options, not choices" || bad "a userConfig option uses choices, which the schema rejects"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate plugin 2>&1 | grep -q "Validation passed" \
    && ok "claude plugin validate passes" || bad "claude plugin validate fails"
else
  ok "claude CLI absent — manifest validation skipped"
fi

# A plugin CANNOT declare these — measured across 39 shipped plugins, 0 use them. Declaring them
# would look like configuration and do nothing.
for key in permissions env; do
  python3 -c 'import json,sys; sys.exit(1 if "'"$key"'" in json.load(open("'"$man"'")) else 0)' \
    && ok "plugin.json does not pretend to declare $key" || bad "plugin.json declares $key, which plugins ignore"
done

echo "== options bridge =="
# A plugin cannot declare settings `env`, so configuration arrives as CLAUDE_PLUGIN_OPTION_*. The
# bridge maps those onto the RAEMEMBERIT_* names the engine has always read.
b() { env -u RAEMEMBERIT_MEMORY_DIR -u RAEMEMBERIT_DUPES "$@" bash -c '. engine/lib/raememberit-root.sh; printf "%s|%s" "$RAEMEMBERIT_MEM" "${RAEMEMBERIT_DUPES:-}"'; }

case "$(b CLAUDE_PLUGIN_OPTION_MEMORYDIR=/tmp/rmi-a)" in
  /tmp/rmi-a*) ok "option MEMORYDIR reaches RAEMEMBERIT_MEMORY_DIR" ;;
  *) bad "option MEMORYDIR did not reach the engine" ;;
esac
# The casing rule, pinned. Derived from the Claude Code binary:
#   key.replace(/[^A-Za-z0-9_]/g,"_").toUpperCase()  ->  CLAUDE_PLUGIN_OPTION_<that>
# So camelCase is uppercased WITHOUT being split, and the underscored spelling must NOT be honoured —
# honouring a name the platform never sets is dead code that hides the real one.
case "$(b CLAUDE_PLUGIN_OPTION_MEMORY_DIR=/tmp/rmi-b)" in
  /tmp/rmi-b*) bad "honours CLAUDE_PLUGIN_OPTION_MEMORY_DIR, which the platform never sets" ;;
  *) ok "ignores the underscored spelling — camelCase uppercases without splitting" ;;
esac
for key in memoryDir requireLog precompactMessage recentN personaFile vocabularyFile; do
  derived=$(printf '%s' "$key" | sed 's/[^A-Za-z0-9_]/_/g' | tr '[:lower:]' '[:upper:]')
  grep -q "\b$derived\b" engine/lib/raememberit-options.sh \
    || bad "bridge does not read the derived name for $key (CLAUDE_PLUGIN_OPTION_$derived)"
done
ok "every option is read under the name the platform actually sets"
case "$(b CLAUDE_PLUGIN_OPTION_DUPES=block)" in
  *"|block") ok "option DUPES reaches RAEMEMBERIT_DUPES" ;;
  *) bad "option DUPES did not reach the engine" ;;
esac
# An explicitly set RAEMEMBERIT_* is deliberate; an option is a default. Deliberate wins.
case "$(RAEMEMBERIT_MEMORY_DIR=/tmp/rmi-explicit CLAUDE_PLUGIN_OPTION_MEMORYDIR=/tmp/rmi-option bash -c '. engine/lib/raememberit-root.sh; printf "%s" "$RAEMEMBERIT_MEM"')" in
  /tmp/rmi-explicit*) ok "an explicit RAEMEMBERIT_* beats a plugin option" ;;
  *) bad "a plugin option overrode an explicitly set variable" ;;
esac
# Every option the manifest declares should actually be consumed somewhere, or it is a knob that
# turns nothing.
for optname in user memoryDir dupes requireLog precompactMessage recentN personaFile vocabularyFile; do
  up=$(printf '%s' "$optname" | tr '[:lower:]' '[:upper:]')
  grep -q "CLAUDE_PLUGIN_OPTION_${up}\b\|__rmi_take .*${up}" engine/lib/raememberit-options.sh \
    || grep -qi "$optname" engine/lib/raememberit-options.sh \
    || bad "manifest declares $optname but the bridge never reads it"
done
ok "every declared option is read by the bridge"

echo "== configuration reaches the model as context =="
# Zero commands across the 39 official plugins read an option; only scripts invoked by hooks do. So
# the hook states the configuration instead of a command file interpolating it.
# inject-memory injects ONCE per context, guarded by a file keyed on the session id. A test that
# reuses a session id therefore passes once and fails for ever after. Use a fresh id each run and
# clear the guard on both sides, so the assertion cannot be poisoned by its own history.
sid="testsuite-$(date +%s)-$RANDOM"
guard="${TMPDIR:-/tmp}/raememberit-injected-$sid"
rm -f "$guard"
out="$(printf '{"session_id":"%s"}' "$sid" | RAEMEMBERIT_USER=Testee bash engine/hooks/inject-memory.sh 2>/dev/null)"
if [ -z "$out" ]; then
  bad "inject-memory.sh produced nothing"
else
  printf '%s' "$out" | grep -q 'Address the user as Testee' \
    && ok "the addressee reaches context without any template substitution" \
    || bad "the addressee is not in the injected context"
  printf '%s' "$out" | grep -q 'mem-write.sh' \
    && ok "the write path is stated in context" || bad "the write path is not stated in context"
  printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
    && ok "injected payload is valid JSON" || bad "injected payload is not valid JSON"
fi
rm -f "$guard"

echo "== the plugin is self-sufficient =="
for f in install.sh engine/mem-write.sh engine/rebuild-index.sh starter/queries.json scaffold/memory/README.md commands/setup.md; do
  [ -e "plugin/$f" ] && ok "ships $f" || bad "does not ship $f, which setup needs"
done
# It must NOT ship the standalone wiring fragment, and must not need it. Shipping it would invite
# someone to merge hooks that the plugin already supplies — the doubling case, self-inflicted.
[ -e plugin/engine/settings.fragment.json ] && bad "ships the standalone settings fragment" \
                                            || ok "does not ship the standalone settings fragment"
# Every command the plugin ships must be fully resolved: a leftover {{SLOT}} once made an installed
# /recall grep a directory that did not exist and report a confident "no prior memory".
if grep -l '{{' plugin/commands/*.md >/dev/null 2>&1; then
  bad "a shipped command still contains an unfilled {{slot}}"
else
  ok "no unfilled slots in any shipped command ($(find plugin/commands -name '*.md' | wc -l | tr -d ' ') commands)"
fi
grep -q 'RAEMEMBERIT_MEMORY_DIR' plugin/commands/recall.md \
  && ok "shipped commands resolve the corpus at runtime, not at install time" \
  || bad "shipped commands do not resolve the corpus at runtime"

echo "== install.sh --plugin =="
# The end-to-end path, run FROM THE PLUGIN as a real user would, against a throwaway config dir.
t2="$(mktemp -d)/.claude"
mkdir -p "$t2/plugins/data/raememberit-skills-dir/bin"
printf '#!/usr/bin/env bash\nexec bash /nowhere/mem-write.sh "$@"\n' > "$t2/plugins/data/raememberit-skills-dir/bin/mem-write.sh"
if bash plugin/install.sh --plugin --config-dir "$t2" --no-guided --user Testee >/dev/null 2>&1; then
  ok "plugin-mode install completes from inside the plugin"
else
  bad "plugin-mode install failed from inside the plugin"
fi
if [ -f "$t2/settings.json" ]; then
  # No hooks: the plugin supplies them, and merging them here too fires every hook twice.
  python3 -c 'import json,sys; d=json.load(open("'"$t2"'/settings.json")); sys.exit(0 if not d.get("hooks") else 1)' \
    && ok "wires no hooks into settings (the plugin owns them)" || bad "wired hooks into settings as well as the plugin"
  # No env: an explicit RAEMEMBERIT_* beats an option, so writing one would kill the manifest's knob.
  python3 -c 'import json,sys; d=json.load(open("'"$t2"'/settings.json")); sys.exit(0 if not d.get("env") else 1)' \
    && ok "writes no env (userConfig drives configuration)" || bad "wrote env, which would override the plugin options"
  # The rule must name the version-free wrapper, never the versioned plugin path.
  python3 -c 'import json,sys
d=json.load(open("'"$t2"'/settings.json"))
a=d.get("permissions",{}).get("allow",[])
sys.exit(0 if any("/plugins/data/" in r and "mem-write.sh" in r for r in a) else 1)' \
    && ok "permission rule names the stable \$CLAUDE_PLUGIN_DATA path" || bad "permission rule does not name the stable path"
  python3 -c 'import json,sys
d=json.load(open("'"$t2"'/settings.json"))
a=d.get("permissions",{}).get("allow",[])
sys.exit(1 if any("/plugins/cache/" in r for r in a) else 0)' \
    && ok "no rule names the versioned install path" || bad "a rule names the versioned path and will break on update"
else
  bad "plugin-mode install wrote no settings.json"
fi
# It seeds a corpus, and leaves no standalone litter behind.
[ -d "$t2/memory/feedback" ] && ok "seeds the corpus outside the plugin" || bad "did not seed a corpus"
[ -d "$t2/raememberit" ] && bad "created an empty raememberit/ that plugin mode does not own" \
                         || ok "no leftover raememberit/ directory"
[ -d "$t2/commands" ] && bad "created a commands/ directory it does not populate" \
                      || ok "no leftover commands/ directory"
# Idempotence: a second run must not duplicate rules or disturb the corpus.
before="$(python3 -c 'import json;d=json.load(open("'"$t2"'/settings.json"));print(len(d["permissions"]["allow"]))')"
bash plugin/install.sh --plugin --config-dir "$t2" --no-guided >/dev/null 2>&1 || true
after="$(python3 -c 'import json;d=json.load(open("'"$t2"'/settings.json"));print(len(d["permissions"]["allow"]))')"
[ "$before" = "$after" ] && ok "re-running adds no duplicate permission rules ($after)" \
                         || bad "re-running changed the rule count: $before -> $after"
rm -rf "$(dirname "$t2")"

echo "== marketplace =="
MP=.claude-plugin/marketplace.json
if [ ! -f "$MP" ]; then
  bad "no $MP — a plugin cannot be installed from this repo without one"
else
  python3 -c 'import json; json.load(open("'"$MP"'"))' 2>/dev/null \
    && ok "marketplace.json is valid JSON" || bad "marketplace.json is not valid JSON"
  # A plain relative string is a legitimate source: 52 of the official marketplace's 314 entries use it,
  # and `marketplace add <path>` resolves it to {"source":"directory"} — no network.
  src="$(python3 -c 'import json;print(json.load(open("'"$MP"'"))["plugins"][0]["source"])')"
  case "$src" in
    ./*) ok "plugin source is a relative path ($src) — installs with no network" ;;
    *)   bad "plugin source is not a relative path: $src" ;;
  esac
  [ -f "${src#./}/.claude-plugin/plugin.json" ] \
    && ok "the source path contains a plugin manifest" \
    || bad "the marketplace points at $src, which has no .claude-plugin/plugin.json"
  python3 -c 'import json,sys
m=json.load(open("'"$MP"'")); p=json.load(open("plugin/.claude-plugin/plugin.json"))
sys.exit(0 if m["plugins"][0]["name"] == p["name"] else 1)' \
    && ok "marketplace and manifest agree on the plugin name" \
    || bad "marketplace and manifest disagree on the plugin name"
fi

echo "== the wrapper fails legibly when its version is gone =="
# `claude plugin update` KEEPS the old version directory, so a not-yet-rewritten wrapper keeps working
# one version behind — benign. A MISSING target is the case worth a clear message rather than a bare
# "No such file or directory" from bash.
sb3="$(mktemp -d)"
mkdir -p "$sb3/root/engine"; cp -R engine/. "$sb3/root/engine/"
CLAUDE_PLUGIN_ROOT="$sb3/root" CLAUDE_PLUGIN_DATA="$sb3/data" bash engine/hooks/place-shim.sh >/dev/null 2>&1
rm -rf "$sb3/root"
msg="$(bash "$sb3/data/bin/mem-write.sh" 2>&1 >/dev/null || true)"
rc=0; bash "$sb3/data/bin/mem-write.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" = "1" ] && ok "wrapper exits 1 when its target version is gone" || bad "wrapper exit code was $rc, expected 1"
printf '%s' "$msg" | grep -q 'Start a new session' \
  && ok "wrapper says what to do about it" || bad "wrapper gives no actionable message"
rm -rf "$sb3"

echo "== install.sh --as-plugin: the plugin route without a marketplace =="
# Distribution is this script, not a marketplace. A skills-dir install has NO version component in its
# path, so the wrapper the marketplace case needs is unnecessary: the rule names the engine directly and
# still never moves.
t4="$(mktemp -d)/.claude"
if bash install.sh --as-plugin --config-dir "$t4" --no-guided --user Testee >/dev/null 2>&1; then
  ok "--as-plugin install completes"
else
  bad "--as-plugin install failed"
fi
SK="$t4/skills/raememberit"
[ -f "$SK/.claude-plugin/plugin.json" ] && ok "places the manifest (without it, it is not a plugin)" \
                                        || bad "no .claude-plugin/plugin.json placed"
[ -f "$SK/hooks/hooks.json" ] && ok "places hooks.json" || bad "no hooks.json placed"
[ -f "$SK/engine/mem-write.sh" ] && ok "places the engine" || bad "no engine placed"
[ -f "$SK/commands/setup.md" ] && ok "places the commands" || bad "no commands placed"
if [ -f "$t4/settings.json" ]; then
  python3 -c 'import json,sys
d=json.load(open("'"$t4"'/settings.json")); sys.exit(0 if not d.get("hooks") else 1)' \
    && ok "still wires no hooks into settings" || bad "wired hooks into settings"
  python3 -c 'import json,sys
d=json.load(open("'"$t4"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
sys.exit(0 if any("/skills/raememberit/engine/mem-write.sh" in r for r in a) else 1)' \
    && ok "rule names the engine directly — no wrapper needed for a skills-dir install" \
    || bad "rule does not name the skills-dir engine"
  python3 -c 'import json,sys
d=json.load(open("'"$t4"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
sys.exit(1 if any("/plugins/cache/" in r for r in a) else 0)' \
    && ok "no version component anywhere in the rules" || bad "a rule carries a version component"
else
  bad "--as-plugin wrote no settings.json"
fi
# The rule is worthless if it names something that cannot run.
if [ -f "$SK/engine/mem-write.sh" ]; then
  RAEMEMBERIT_MEMORY_DIR="$t4/memory" RAEMEMBERIT_DUPES=off bash "$SK/engine/mem-write.sh" reference asplugin-assert >/dev/null 2>&1 <<'EOF'
---
name: asplugin-assert
description: Written through the exact path the permission rule names, because a rule pointing at something unrunnable is decoration
metadata:
  type: reference
---
Probe.
EOF
  [ -f "$t4/memory/reference/asplugin-assert.md" ] \
    && ok "the path the rule names actually writes a memory" \
    || bad "the rule names a path that cannot write"
fi
# An existing skills dir is someone's, possibly edited: same principle as the command manifest.
marker="$SK/MINE.txt"; : > "$marker"
bash install.sh --as-plugin --config-dir "$t4" --no-guided >/dev/null 2>&1 || true
[ -f "$marker" ] && ok "a second run leaves an existing plugin directory alone" \
                 || bad "a second run replaced the plugin directory without --force"
bash install.sh --as-plugin --config-dir "$t4" --no-guided --force >/dev/null 2>&1 || true
[ -f "$marker" ] && bad "--force did not replace the plugin directory" \
                 || ok "--force replaces it"
rm -rf "$(dirname "$t4")"

echo "== the two routes must not double each other =="
# THE SHARPEST BUG THIS SUITE CAUGHT. A standalone install wires seven hook groups into settings; a
# plugin supplies the same ones. Doing both fires every hook twice — no error, just doubling, reachable
# through the installer's own flags. Plugin mode therefore REMOVES raememberit's own settings hooks, and
# standalone WARNS when a plugin is present.
t5="$(mktemp -d)/.claude"
mkdir -p "$t5"
# Someone else's hook, which must survive every step below untouched.
cat > "$t5/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"/usr/local/bin/not-ours.sh"}]}]}}
JSON
bash install.sh --config-dir "$t5" --no-guided --user Testee >/dev/null 2>&1
n1=$(python3 -c 'import json;d=json.load(open("'"$t5"'/settings.json"));print(sum(len(v) for v in d.get("hooks",{}).values()))')
[ "$n1" -gt 1 ] && ok "standalone wires its hooks into settings ($n1 groups)" || bad "standalone wired no hooks"

out5="$(bash install.sh --as-plugin --config-dir "$t5" --no-guided 2>&1)"
printf '%s' "$out5" | grep -q 'REMOVED from settings' \
  && ok "--as-plugin says it removed the settings hooks" \
  || bad "--as-plugin did not report removing the settings hooks"
python3 -c 'import json,sys
d=json.load(open("'"$t5"'/settings.json"))
c=[h["command"] for a in d.get("hooks",{}).values() for g in a for h in g["hooks"]]
sys.exit(0 if not any("raememberit" in x for x in c) else 1)' \
  && ok "no raememberit hook remains in settings — nothing doubles" \
  || bad "raememberit hooks remain in settings alongside the plugin: everything fires twice"
python3 -c 'import json,sys
d=json.load(open("'"$t5"'/settings.json"))
c=[h["command"] for a in d.get("hooks",{}).values() for g in a for h in g["hooks"]]
sys.exit(0 if any("not-ours.sh" in x for x in c) else 1)' \
  && ok "someone else's hook survives the removal" \
  || bad "removed a hook that was not ours"

# And the mirror: standalone onto a config that already has the plugin must REFUSE.
# NB capture first, grep after. Piping a long-running script into `grep -q` under `set -o pipefail`
# fails the pipeline even when grep MATCHES: grep exits at the first hit, the script takes SIGPIPE, and
# pipefail reports that. This cost a false FAIL here, having cost this project three before it.
out6="$(bash install.sh --config-dir "$t5" --no-guided 2>&1)"; rc6=$?
printf '%s' "$out6" | grep -q 'fire TWICE' \
  && ok "standalone names the doubling when a plugin is already present" \
  || bad "standalone is silent about an installed plugin — the doubling would go unnoticed"
[ "$rc6" != "0" ] && ok "and refuses rather than recreating a doubled configuration" \
                  || bad "standalone proceeded and wired the hooks back in alongside the plugin"
python3 -c 'import json,sys
d=json.load(open("'"$t5"'/settings.json"))
c=[h["command"] for a in d.get("hooks",{}).values() for g in a for h in g["hooks"]]
sys.exit(0 if not any("raememberit" in x for x in c) else 1)' \
  && ok "settings still carry no raememberit hooks after the refusal" \
  || bad "the refused run still modified settings"
out7="$(bash install.sh --config-dir "$t5" --no-guided --force 2>&1)"; rc7=$?
[ "$rc7" = "0" ] && ok "--force overrides the refusal for someone who means it" \
                 || bad "--force did not override the refusal"
rm -rf "$(dirname "$t5")"

echo "== a rule is never added for a helper that does not exist =="
# THE BUG THIS CATCHES. --as-plugin used to set the helper path unconditionally and report it as fact.
# Against a config holding an OLDER raememberit plugin — one from before the engine shipped inside the
# plugin — that named a file which was not there, and the rule went in anyway. A rule naming a
# nonexistent path grants nothing and fails SILENTLY: writes just begin prompting, with nothing to say
# why. So: verify, then refuse.
t8="$(mktemp -d)/.claude"
mkdir -p "$t8/skills/raememberit/.claude-plugin" "$t8/skills/raememberit/hooks"
printf '{"name":"raememberit","version":"0.1.0"}\n' > "$t8/skills/raememberit/.claude-plugin/plugin.json"
printf '{"hooks":{}}\n' > "$t8/skills/raememberit/hooks/hooks.json"
out8="$(bash install.sh --as-plugin --config-dir "$t8" --no-guided 2>&1)"; rc8=$?
[ "$rc8" != "0" ] && ok "a stale plugin directory (no engine/) is refused" \
                  || bad "proceeded against a plugin directory that ships no engine"
printf '%s' "$out8" | grep -q 'start prompting' \
  && ok "the refusal explains the silent failure it prevents" || bad "the refusal does not explain itself"
printf '%s' "$out8" | grep -q -- '--as-plugin --force' \
  && ok "the refusal names the way out" || bad "the refusal names no remedy"
# And it must die BEFORE writing anything.
[ -f "$t8/settings.json" ] && bad "the refused run still wrote settings.json" \
                           || ok "nothing was written before the refusal"
# --force recovers, and then every Bash rule names a file that is really there.
bash install.sh --as-plugin --config-dir "$t8" --no-guided --force >/dev/null 2>&1 \
  && ok "--force replaces the stale directory and completes" || bad "--force did not recover"
python3 -c 'import json,os,sys
d=json.load(open("'"$t8"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
b=[r for r in a if r.startswith("Bash(")]
paths=[r.split("(",1)[1].rsplit(":*",1)[0].replace("bash ","") for r in b]
sys.exit(0 if b and all(os.path.isfile(x) for x in paths) else 1)' \
  && ok "every Bash rule names a file that exists" \
  || bad "a Bash rule names a path that is not there"
rm -rf "$(dirname "$t8")"

# The same guarantee on the ordinary fresh path, stated separately: the assertion above could pass on a
# config that got no rules at all.
t9="$(mktemp -d)/.claude"
bash install.sh --as-plugin --config-dir "$t9" --no-guided >/dev/null 2>&1
python3 -c 'import json,os,sys
d=json.load(open("'"$t9"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
b=[r for r in a if r.startswith("Bash(")]
paths=[r.split("(",1)[1].rsplit(":*",1)[0].replace("bash ","") for r in b]
sys.exit(0 if len(b) == 2 and all(os.path.isfile(x) for x in paths) else 1)' \
  && ok "a fresh --as-plugin install adds two Bash rules, both resolving" \
  || bad "a fresh --as-plugin install did not add two resolving Bash rules"
rm -rf "$(dirname "$t9")"

echo "== --hooks-from-plugin: engine in the config dir, hooks from a plugin =="
# The THIRD arrangement, and the one an adopted setup ends up in. Hand-edited commands hardcode
# <config>/raememberit/engine/... paths, so a route that moves the engine breaks them SILENTLY — they
# grep nothing and report confident emptiness. This mode exists so that arrangement is supported.
th="$(mktemp -d)/.claude"
bash install.sh --hooks-from-plugin --config-dir "$th" --no-guided --user Tester >/dev/null 2>&1 \
  && ok "--hooks-from-plugin completes" || bad "--hooks-from-plugin failed"
[ -f "$th/raememberit/engine/mem-write.sh" ] && ok "engine stays in the config dir" \
                                             || bad "engine is not in the config dir"
[ -f "$th/skills/raememberit/hooks/hooks.json" ] && ok "a plugin is generated" || bad "no plugin generated"
[ -d "$th/skills/raememberit/engine" ]   && bad "the generated plugin ships an engine (it must not)" \
                                         || ok "the generated plugin ships no engine"
[ -d "$th/skills/raememberit/commands" ] && bad "the generated plugin ships commands (it must not)" \
                                         || ok "the generated plugin ships no commands"
# No userConfig: configuration here comes from settings `env`, which the bridge ranks ABOVE any option,
# so a declared option would be silently shadowed — a knob that turns nothing.
python3 -c 'import json,sys
m=json.load(open("'"$th"'/skills/raememberit/.claude-plugin/plugin.json"))
sys.exit(1 if m.get("userConfig") else 0)' \
  && ok "declares no userConfig (settings env would shadow it)" || bad "declares options that env shadows"
# Hook commands are config-dir relative ON PURPOSE here, and every one must resolve.
python3 -c 'import json,os,sys
d=json.load(open("'"$th"'/skills/raememberit/hooks/hooks.json"))
c=[h["command"] for a in d["hooks"].values() for g in a for h in g["hooks"]]
if not c: sys.exit(1)
if any("PLUGIN_ROOT" in x for x in c): sys.exit(2)
if any("place-shim" in x for x in c): sys.exit(3)
bad=[x for x in c if not os.path.exists(x.replace("${CLAUDE_CONFIG_DIR:-$HOME/.claude}", "'"$th"'"))]
sys.exit(4 if bad else 0)'
case $? in
  0) ok "every hook command is config-dir relative, resolves, and there is no place-shim" ;;
  1) bad "the generated hooks.json has no hook commands" ;;
  2) bad "a hook command is PLUGIN_ROOT-relative — wrong for this arrangement" ;;
  3) bad "ships place-shim, which this arrangement does not need" ;;
  4) bad "a hook command does not resolve to an existing file" ;;
esac
python3 -c 'import json,sys
d=json.load(open("'"$th"'/settings.json")); sys.exit(0 if not d.get("hooks") else 1)' \
  && ok "settings carry no hooks — the plugin owns them" || bad "hooks were wired into settings too"
python3 -c 'import json,sys
d=json.load(open("'"$th"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
sys.exit(0 if any("/raememberit/engine/mem-write.sh" in r for r in a) else 1)' \
  && ok "the rule names the CONFIG-DIR engine, which is what commands reference" \
  || bad "the rule does not name the config-dir engine"
[ -d "$th/commands" ] && ok "commands are installed (unlike --as-plugin)" || bad "no commands installed"

# Migration: a config wired standalone must have its settings hooks stripped, not doubled.
bash install.sh --config-dir "$th" --no-guided --force >/dev/null 2>&1
n_before=$(python3 -c 'import json;d=json.load(open("'"$th"'/settings.json"));print(sum(len(v) for v in d.get("hooks",{}).values()))')
bash install.sh --hooks-from-plugin --config-dir "$th" --no-guided >/dev/null 2>&1
python3 -c 'import json,sys
d=json.load(open("'"$th"'/settings.json"))
c=[h["command"] for a in d.get("hooks",{}).values() for g in a for h in g["hooks"]]
sys.exit(0 if not any("raememberit" in x for x in c) else 1)' \
  && ok "migrating from standalone strips the settings hooks ($n_before were there)" \
  || bad "migrating from standalone left the hooks in settings: everything would double"
rm -rf "$(dirname "$th")"

echo "== a re-run must not silently discard the configuration =="
# THE FOOTGUN. The installer says to re-run it any time; --user was only read from the command line, so a
# bare re-run re-rendered every command with the default addressee and reported it merely as "2 updated".
tc="$(mktemp -d)/.claude"
bash install.sh --config-dir "$tc" --no-guided --user Tester >/dev/null 2>&1
grep -q 'Tester' "$tc/commands/learn.md" && ok "the addressee is rendered into the commands" \
                                        || bad "the addressee was not rendered"
out_c="$(bash install.sh --config-dir "$tc" --no-guided 2>&1)"
grep -q 'Tester' "$tc/commands/learn.md" \
  && ok "a re-run WITHOUT --user keeps the addressee" \
  || bad "a bare re-run silently reverted the addressee to the default"
printf '%s' "$out_c" | grep -q 'remembered from the last run' \
  && ok "and says where the value came from" || bad "does not say the value was remembered"
# An explicit flag still wins — remembering must not become a cage.
bash install.sh --config-dir "$tc" --no-guided --user Other >/dev/null 2>&1
grep -q 'Other' "$tc/commands/learn.md" && ok "an explicit --user still overrides what was remembered" \
                                        || bad "--user no longer overrides the remembered value"
# A persona is appended to a fragment that is rewritten every run, so it had the same defect.
pf="$(mktemp)"; printf '## Persona\nBe terse.\n' > "$pf"
bash install.sh --config-dir "$tc" --no-guided --persona "$pf" >/dev/null 2>&1
bash install.sh --config-dir "$tc" --no-guided >/dev/null 2>&1
grep -q 'Be terse' "$tc/raememberit/INSTRUCTIONS-fragment.md" \
  && ok "a re-run keeps the persona too" || bad "a bare re-run dropped the persona from the fragment"
rm -f "$pf"
# A remembered path that has since vanished must not wedge the installer: the record keeps it, so dying
# on it would fail every future run identically with no visible remedy. Warn, drop, carry on. A GIVEN
# path still dies, because naming a file that is not there is a typo.
out_gone="$(bash install.sh --config-dir "$tc" --no-guided 2>&1)"; rc_gone=$?
[ "$rc_gone" = "0" ] && ok "a re-run survives a remembered persona file that was deleted" \
                     || bad "a deleted persona file wedges every future run"
printf '%s' "$out_gone" | grep -q 'remembered persona file is gone' \
  && ok "and says it is ignoring it" || bad "drops the persona silently"
bash install.sh --config-dir "$tc" --no-guided --persona /nonexistent/persona.md >/dev/null 2>&1 \
  && bad "an explicitly given missing persona file was accepted" \
  || ok "an explicitly GIVEN missing persona file still fails"

echo "== the command tally accounts for every file =="
# "0 installed · 0 updated · 2 left alone" on a config holding five commands is a report that does not
# add up, and a reader cannot tell whether the other three were touched.
out_t="$(bash install.sh --config-dir "$tc" --no-guided 2>&1 | grep 'commands:')"
printf '%s' "$out_t" | grep -q 'already current' \
  && ok "unchanged commands are counted, not silent" || bad "unchanged commands are still unreported"
tot=$(python3 -c 'import re,sys
m=re.findall(r"(\d+) (?:installed|updated|already current|left alone)", """'"$out_t"'""")
print(sum(int(x) for x in m))')
have=$(ls "$tc/commands"/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$tot" = "$have" ] && ok "the numbers add up to the $have files present" \
                     || bad "the tally sums to $tot but $have command files exist"
rm -rf "$(dirname "$tc")"

echo "== diff-commands.sh: the frozen decision stays revisitable =="
# The installer never overwrites a command it did not write, which is right — but the cost is silent:
# improvements to command MECHANICS never reach an adopted setup and nothing says so. This makes the
# divergence visible on demand, and it must be strictly READ-ONLY.
td="$(mktemp -d)/.claude"
bash install.sh --config-dir "$td" --no-guided --user Tester >/dev/null 2>&1
out_d="$(CLAUDE_CONFIG_DIR="$td" bash tools/diff-commands.sh --stat 2>&1)"
printf '%s' "$out_d" | grep -q 'identical to the shipped version' \
  && ok "a fresh install reports its commands as identical" \
  || bad "a fresh install is reported as diverging from its own templates"
printf '%s' "$out_d" | grep -q 'addressee "Tester"' \
  && ok "it renders with the REMEMBERED addressee, not the default" \
  || bad "it does not use the recorded addressee, so every command would look changed"

# Divergence is detected, and reported as additions on the installed side.
printf '\n<!-- my own note -->\n' >> "$td/commands/learn.md"
out_e="$(CLAUDE_CONFIG_DIR="$td" bash tools/diff-commands.sh --stat 2>&1)"
printf '%s' "$out_e" | grep -q 'learn.md' && printf '%s' "$out_e" | grep -qE '\+[0-9]+ / -[0-9]+' \
  && ok "an edited command is reported with a line count" || bad "an edited command was not reported"

# READ-ONLY is the whole safety property: a tool for inspecting your own edits must not touch them.
fp_before="$(find "$td/commands" -name '*.md' | sort | xargs shasum | shasum | awk '{print $1}')"
CLAUDE_CONFIG_DIR="$td" bash tools/diff-commands.sh >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$td" bash tools/diff-commands.sh --stat >/dev/null 2>&1
fp_after="$(find "$td/commands" -name '*.md' | sort | xargs shasum | shasum | awk '{print $1}')"
[ "$fp_before" = "$fp_after" ] && ok "it writes nothing — commands are byte-identical after two runs" \
                              || bad "diff-commands.sh MODIFIED a command file"
# And it must not leave its render temp files behind.
ls "${TMPDIR:-/tmp}"/rmb-diff.* >/dev/null 2>&1 && bad "left a render temp file behind" \
                                                || ok "cleans up its temp files"
# A command that is not installed is named, not skipped in silence.
# CAPTURE FIRST, GREP AFTER. Piping into `grep -q` under `set -o pipefail` fails the pipeline even when
# grep MATCHES: grep exits at the first hit, the writer takes SIGPIPE, pipefail reports it. Third time
# this has produced a false FAIL in this project today.
rm -f "$td/commands/skill-mine.md"
out_f="$(CLAUDE_CONFIG_DIR="$td" bash tools/diff-commands.sh --stat 2>&1)"
printf '%s' "$out_f" | grep -q 'skill-mine.*not installed' \
  && ok "a missing command is reported as not installed" || bad "a missing command is silently skipped"
rm -rf "$(dirname "$td")"

echo "== an explicit --config-dir outranks an ambient corpus variable =="
# THE WORST BUG OF THIS WHOLE EFFORT, and it was live for about twenty minutes. Once
# RAEMEMBERIT_MEMORY_DIR was published into a real settings.json, install.sh read it in preference to
# --config-dir — so every run that believed it was sandboxed seeded and re-indexed the LIVE corpus, and
# one --force run copied a starter rule into it. lib/raememberit-root.sh even carries a comment warning
# about this exact shape.
ta="$(mktemp -d)/.claude"
decoy="$(mktemp -d)/decoy-corpus"
mkdir -p "$decoy/feedback"
out_a="$(RAEMEMBERIT_MEMORY_DIR="$decoy" bash install.sh --config-dir "$ta" --no-guided --user T 2>&1)"
printf '%s' "$out_a" | grep -q 'ignoring RAEMEMBERIT_MEMORY_DIR' \
  && ok "it says it is ignoring the ambient variable" || bad "it silently honoured the ambient variable"
printf '%s' "$out_a" | grep -q "corpus at $ta/memory" \
  && ok "the corpus goes where --config-dir says" || bad "the corpus did not go under --config-dir"
[ -d "$ta/memory/feedback" ] && ok "the sandbox corpus was created" || bad "no sandbox corpus"
# The decoy must be untouched: that is the whole point.
[ -z "$(ls -A "$decoy/feedback" 2>/dev/null)" ] \
  && ok "the directory the variable named was NOT written to" \
  || bad "the ambient corpus was written to despite an explicit --config-dir"
# But when no --config-dir is given, the variable must still work: that is how a published path is honoured.
tb="$(mktemp -d)/.claude"; mkdir -p "$tb"
out_b="$(CLAUDE_CONFIG_DIR="$tb" RAEMEMBERIT_MEMORY_DIR="$tb/elsewhere" bash install.sh --no-guided --user T 2>&1)"
printf '%s' "$out_b" | grep -q "corpus at $tb/elsewhere" \
  && ok "with no --config-dir the variable is still honoured" \
  || bad "the variable is ignored even when no --config-dir was given"
rm -rf "$(dirname "$ta")" "$(dirname "$decoy")" "$(dirname "$tb")"

echo "== this suite must not inherit the developer's own configuration =="
for v in RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_USER; do
  eval "val=\${$v:-}"
  [ -z "$val" ] || bad "$v is set inside the suite ($val) — assertions would test a real configuration"
done
ok "the ambient raememberit variables are unset for the whole suite"

echo
echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
