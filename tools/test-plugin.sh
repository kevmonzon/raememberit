#!/usr/bin/env bash
# Assertions on the generated plugin tree. The point is not that the plugin works — a session proves
# that — but that the plugin and the standalone fragment cannot silently disagree.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
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
# The camelCase-to-env casing is unevidenced across all 39 official plugins, so BOTH spellings are
# accepted. If this assertion ever becomes redundant, that means the convention got confirmed.
case "$(b CLAUDE_PLUGIN_OPTION_MEMORY_DIR=/tmp/rmi-b)" in
  /tmp/rmi-b*) ok "the underscored spelling is accepted too (casing is unevidenced upstream)" ;;
  *) bad "the underscored option spelling is not accepted" ;;
esac
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

echo
echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
