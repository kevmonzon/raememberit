#!/usr/bin/env bash
# The real install -> update -> uninstall cycle, against a throwaway config directory.
#
# WHY THIS IS NOT IN test-all.sh. `claude plugin install` from a directory marketplace CLONES THE GIT
# STATE, not the working tree — it records a gitCommitSha. So this exercises the last COMMIT, which
# makes it wrong as a pre-commit gate and right as a post-commit one. It is also slow, and it needs the
# `claude` CLI. CI runs it as its own step after the fast suites.
#
# It answers the one question the rest of the design rests on and cannot argue its way out of:
# DOES AN UPDATE DISTURB A CORPUS? Everything else here — corpus outside the plugin, engine inside it,
# a wrapper at a version-free path — exists to make a wholesale directory replacement harmless.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

command -v claude >/dev/null 2>&1 || { echo "  claude CLI absent — lifecycle cycle skipped"; echo; echo "  0 passed, 0 failed"; exit 0; }
git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1 || { echo "  not a git repo — install clones git state, so skipped"; echo; echo "  0 passed, 0 failed"; exit 0; }

SB="$(mktemp -d)/.claude"; mkdir -p "$SB"
export CLAUDE_CONFIG_DIR="$SB"
cleanup() { rm -rf "$(dirname "$SB")"; }
trap cleanup EXIT

MEM="$SB/memory"
# Content-only: EXCLUDE the generated indexes, which legitimately change on any rebuild. An earlier
# version of this instrument included them and reported a corpus as "changed" when nothing had moved.
fp() { find "$MEM" -name '*.md' -not -name 'MEMORY.md' -not -name 'MEMORY-CATALOG.md' 2>/dev/null | sort | xargs shasum 2>/dev/null | shasum | awk '{print $1}'; }
ver() { python3 -c 'import json,sys
try: d=json.load(open("'"$SB"'/plugins/installed_plugins.json"))
except Exception: print(""); sys.exit()
e=d.get("plugins",{}).get("raememberit@raememberit") or []
print(e[0]["version"] if e else "")' 2>/dev/null; }

echo "== install =="
claude plugin marketplace add "$ROOT" >/dev/null 2>&1 \
  && ok "marketplace added from a local path" || bad "could not add the marketplace"
if claude plugin install raememberit@raememberit >/dev/null 2>&1; then
  ok "plugin installed (version $(ver))"
else
  bad "plugin install failed"; echo; echo "  $pass passed, $fail failed"; exit 1
fi
INSTALLED="$(ver)"
P="$SB/plugins/cache/raememberit/raememberit/$INSTALLED"
[ -d "$P" ] && ok "installed at a versioned cache path" || bad "no versioned cache path"
[ -f "$P/install.sh" ] && ok "the installed plugin carries its own installer" || bad "installer not shipped"

echo "== the restart, then setup =="
# ORDER MATTERS, and getting it wrong here is instructive: install.sh can only add the permission rule
# once the wrapper EXISTS, because it discovers the path rather than constructing it. The real sequence
# is install -> restart (the SessionStart hook places the wrapper) -> /raememberit:setup. Running setup
# first is the documented first-run case, where it correctly adds no Bash rule and says to re-run.
SHIM="$SB/plugins/data/raememberit-raememberit/bin/mem-write.sh"
bash "$P/install.sh" --plugin --config-dir "$SB" --no-guided >/dev/null 2>&1 || true
python3 -c 'import json,sys
d=json.load(open("'"$SB"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
sys.exit(0 if not any("mem-write" in r for r in a) else 1)' \
  && ok "before any restart, setup adds no Bash rule (nothing to point at yet)" \
  || bad "a Bash rule was added while no wrapper existed"

# Now the restart: the SessionStart hook places the wrapper.
CLAUDE_PLUGIN_ROOT="$P" CLAUDE_PLUGIN_DATA="$SB/plugins/data/raememberit-raememberit" \
  bash "$P/engine/hooks/place-shim.sh" >/dev/null 2>&1
[ -x "$SHIM" ] && ok "wrapper placed at the version-free path" || bad "wrapper not placed"

echo "== seed a corpus, and write into it =="
bash "$P/install.sh" --plugin --config-dir "$SB" --no-guided --user Tester >/dev/null 2>&1 \
  && ok "corpus seeded through the installed plugin" || bad "seeding failed"
python3 -c 'import json,sys
d=json.load(open("'"$SB"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
sys.exit(0 if any("'"$SHIM"'" in r for r in a) else 1)' \
  && ok "re-running after the restart adds the rule, aimed at the wrapper" \
  || bad "the rule was not added even though the wrapper exists"
RAEMEMBERIT_MEMORY_DIR="$MEM" RAEMEMBERIT_DUPES=off bash "$SHIM" reference lifecycle-probe >/dev/null 2>&1 <<'EOF'
---
name: lifecycle-probe
description: Written before a plugin update so that the update can be proven not to disturb a corpus
metadata:
  type: reference
---
Written before `claude plugin update`. Its survival is the assertion.
EOF
[ -f "$MEM/reference/lifecycle-probe.md" ] && ok "a memory can be written through the wrapper" || bad "the write failed"

BEFORE="$(fp)"; N="$(find "$MEM" -name '*.md' | wc -l | tr -d ' ')"
MTIME="$(stat -f '%m' "$MEM/reference/lifecycle-probe.md" 2>/dev/null || stat -c '%Y' "$MEM/reference/lifecycle-probe.md" 2>/dev/null)"

echo "== update =="
# The repo is at one version; to prove an update we need a different one. Bump the MANIFEST inside the
# cached copy and re-point the marketplace at it? No — that tests nothing real. Instead: if the repo's
# version already equals the installed one, `update` is a no-op and the corpus assertion still holds,
# which is the assertion that matters. Report which case ran, rather than pretending.
claude plugin update raememberit@raememberit >/dev/null 2>&1 || true
AFTER_VER="$(ver)"
if [ "$AFTER_VER" != "$INSTALLED" ]; then
  ok "version moved $INSTALLED -> $AFTER_VER"
else
  ok "update was a no-op at $INSTALLED (repo and install already agree)"
fi

echo "== the assertion the design rests on =="
[ "$BEFORE" = "$(fp)" ] && ok "corpus is byte-identical after the update" \
                        || bad "THE UPDATE CHANGED THE CORPUS — the premise is wrong"
NOW_MTIME="$(stat -f '%m' "$MEM/reference/lifecycle-probe.md" 2>/dev/null || stat -c '%Y' "$MEM/reference/lifecycle-probe.md" 2>/dev/null)"
[ "$MTIME" = "$NOW_MTIME" ] && ok "mtimes untouched too (not merely rewritten identically)" \
                            || bad "the file was rewritten: mtime moved"
[ "$N" = "$(find "$MEM" -name '*.md' | wc -l | tr -d ' ')" ] && ok "no memory added or removed" || bad "the file count changed"

echo "== the wrapper self-heals onto the new version =="
NEWP="$SB/plugins/cache/raememberit/raememberit/$AFTER_VER"
CLAUDE_PLUGIN_ROOT="$NEWP" CLAUDE_PLUGIN_DATA="$SB/plugins/data/raememberit-raememberit" \
  bash "$NEWP/engine/hooks/place-shim.sh" >/dev/null 2>&1
grep -q "$AFTER_VER" "$SHIM" && ok "wrapper repoints onto $AFTER_VER" || bad "wrapper did not repoint"
python3 -c 'import json,sys
d=json.load(open("'"$SB"'/settings.json")); a=d.get("permissions",{}).get("allow",[])
sys.exit(0 if any("'"$SHIM"'" in r for r in a) else 1)' \
  && ok "the permission rule still names the wrapper — it never moved" \
  || bad "the permission rule no longer matches the wrapper"

echo "== uninstall =="
claude plugin uninstall raememberit@raememberit >/dev/null 2>&1 \
  && ok "plugin uninstalled" || bad "uninstall failed"
[ "$BEFORE" = "$(fp)" ] && ok "MEMORIES SURVIVE the uninstall, byte-identical" \
                        || bad "the uninstall touched the corpus"
[ -d "$SB/plugins/data/raememberit-raememberit" ] \
  && bad "the data directory survived the uninstall" \
  || ok "the data directory (and the wrapper) is removed"
# Known leftovers, documented in protocol/setup.md rather than pretended away.
left=$(python3 -c 'import json
d=json.load(open("'"$SB"'/settings.json")); print(len([r for r in d.get("permissions",{}).get("allow",[]) if "mem-write" in r]))')
[ "$left" -gt 0 ] && ok "permission rules remain ($left) — setup.md tells the user to clear them" \
                  || bad "expected leftover permission rules; setup.md documents clearing them"

echo
echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
