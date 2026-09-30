#!/usr/bin/env bash
# Does an instance installed by an OLDER version update properly with this one? Nine cells: three
# released versions, extracted from git history, times three install routes — each used like a person
# would (their own memories, an edited command, a deleted starter, their own hook, a non-ASCII
# setting), then updated with the working tree's front door.
#
#     tools/test-upgrade-matrix.sh
#
# WHY THIS EXISTS. "Re-running is the upgrade" was true on the route the author uses and false on
# another: the front door ran the recommended route for every update, and an --as-plugin install
# came out with two engines and a status that reported an update for ever. Found 2026-10-01 by
# running exactly this, after 0.6.1 had shipped. Needs git history (git archive of pinned commits),
# so it skips itself on a shallow clone; CI checks out with full depth for it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
unset RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_USER RAEMEMBERIT_PRECOMPACT_MSG RAEMEMBERIT_RECENT_N 2>/dev/null || true
W="${TMPDIR:-/tmp}/raememberit-matrix.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '    FAIL  %s\n' "$1"; }

# Pinned: the commit that cut each version. A version whose commit is not in this clone is skipped
# and said so; a skip is "not measured here", never a pass.
VERSIONS="0.4.0:a0f0aa1 0.5.2:934f02c 0.6.0:513e996 0.6.1:937fff4"
NEW_VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"

cell() {  # OLDKIT ROUTE CELLDIR
  local OLD="$1" ROUTE="$2" C="$3" T="$3/.claude"; mkdir -p "$T"
  export CLAUDE_CONFIG_DIR="$T"
  local flag=""; [ "$ROUTE" = standalone ] || flag="--$ROUTE"
  bash "$OLD/install.sh" $flag --config-dir "$T" --no-guided --user Casey >"$C/old.log" 2>&1 || { bad "old install failed: $(tail -1 "$C/old.log")"; return; }
  local MEM="$T/memory" ENG="$T/raememberit/engine"; [ "$ROUTE" = as-plugin ] && ENG="$T/skills/raememberit/engine"
  printf -- '---\nname: their-rule\ndescription: A rule the user wrote themselves under the old version, which must survive verbatim\nmetadata:\n  type: feedback\n---\n\nbody\n\n**Why:** theirs.\n**How to apply:** keep it.\n' | RAEMEMBERIT_DUPES=off bash "$ENG/mem-write.sh" feedback their-rule >/dev/null 2>&1
  printf -- '---\nname: their-fact\ndescription: A reference fact written under the old version about the staging VPN requirement\nmetadata:\n  type: reference\n---\n\nbody\n' | RAEMEMBERIT_DUPES=off bash "$ENG/mem-write.sh" reference their-fact >/dev/null 2>&1
  printf '# a session log\n' | bash "$ENG/mem-write.sh" log old-session >/dev/null 2>&1
  [ "$ROUTE" = as-plugin ] || printf '\n<!-- my edit -->\n' >> "$T/commands/learn.md"
  rm -f "$MEM/feedback/shell-dialect-traps.md"
  python3 - "$T/settings.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p))
d.setdefault("hooks",{}).setdefault("SessionStart",[]).append({"matcher":"","hooks":[{"type":"command","command":"/usr/local/bin/their-own.sh"}]})
d.setdefault("env",{})["THEIR_NOTE"]="keep — dash"; d["theme"]="dark"
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False)
PY
  fp(){ find "$MEM/feedback" "$MEM/project" "$MEM/reference" "$MEM/interactions" -name '*.md' 2>/dev/null | sort | xargs shasum 2>/dev/null | shasum | awk '{print $1}'; }
  local BEFORE; BEFORE=$(fp)
  bash "$ROOT/raememberit" status --config-dir "$T" >"$C/status.log" 2>&1; local rc=$?
  [ "$rc" = 1 ] && grep -q 'raememberit update' "$C/status.log" && ok || bad "status did not offer the update (rc=$rc)"
  bash "$ROOT/raememberit" update --yes --config-dir "$T" >"$C/update.log" 2>&1; rc=$?
  [ "$rc" = 0 ] && ok || { bad "update rc=$rc"; sed 's/\x1b\[[0-9;]*m//g' "$C/update.log" | tail -6 | sed 's/^/          /'; }
  [ "$(fp)" = "$BEFORE" ] && ok || bad "their memories changed"
  [ ! -f "$MEM/feedback/shell-dialect-traps.md" ] && ok || bad "a deleted starter came back"
  [ -f "$MEM/.seeded-starters" ] && ok || bad "no seed record after the update"
  if [ "$ROUTE" != as-plugin ]; then grep -q 'my edit' "$T/commands/learn.md" && ok || bad "their edited command was overwritten"; fi
  grep -q 'their-own.sh' "$T/settings.json" && grep -q '"dark"' "$T/settings.json" && ok || bad "their own hook or setting was lost"
  grep -q 'keep — dash' "$T/settings.json" && ok || bad "their non-ASCII setting was escaped or lost"
  local NENG="$T/raememberit/engine"; [ "$ROUTE" = as-plugin ] && NENG="$T/skills/raememberit/engine"
  if diff -rq "$ROOT/engine" "$NENG" 2>/dev/null | grep -qv settings.fragment.json; then bad "engine differs from the working tree"; else ok; fi
  if [ "$ROUTE" = as-plugin ]; then [ ! -d "$T/raememberit/engine" ] && ok || bad "a second engine appeared in the config dir"; fi
  local HJ="$T/skills/raememberit/hooks/hooks.json" want; want=$(jq '[.hooks[][].hooks[]]|length' "$ROOT/engine/settings.fragment.json")
  [ "$ROUTE" = as-plugin ] && want=$((want+1))   # place-shim
  if [ -f "$HJ" ]; then
    [ "$(jq '[.hooks[][].hooks[]]|length' "$HJ")" = "$want" ] && ok || bad "plugin carries $(jq '[.hooks[][].hooks[]]|length' "$HJ") hooks, expected $want"
    python3 -c 'import json,sys;d=json.load(open("'"$T"'/settings.json"));c=[h["command"] for a in d.get("hooks",{}).values() for g in a for h in g["hooks"]];sys.exit(1 if any("raememberit" in x for x in c) else 0)' && ok || bad "raememberit hooks also in settings — doubled"
    local miss=0 c; for c in $(jq -r '.hooks[][].hooks[].command' "$HJ" | sed "s|\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}|$T|; s|\${CLAUDE_PLUGIN_ROOT}|$T/skills/raememberit|"); do [ -x "$c" ] || miss=$((miss+1)); done
    [ "$miss" = 0 ] && ok || bad "$miss hook(s) point at a missing file"
  else bad "no hooks plugin after the update"; fi
  printf '{"session_id":"mx","prompt":"the staging VPN requirement for the deploy, remind me"}' | env RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$NENG/hooks/context-router.sh" >/dev/null 2>"$C/router.err"; rc=$?
  [ "$rc" = 0 ] && [ ! -s "$C/router.err" ] && grep -q 'their-fact' "$MEM/.recall-log" 2>/dev/null && ok || bad "the router did not run clean over the upgraded corpus"
  rm -f "${TMPDIR:-/tmp}"/raememberit-surfaced-mx
  bash "$NENG/rebuild-index.sh" >/dev/null 2>&1; grep -q 'their-rule' "$MEM/MEMORY.md" && ok || bad "their old rule is missing from the new index"
  bash "$ROOT/raememberit" update --yes --config-dir "$T" >"$C/update2.log" 2>&1
  grep -q 'nothing to update' "$C/update2.log" && ok || bad "a second update is not a no-op"
  bash "$ROOT/raememberit" status --config-dir "$T" >"$C/status2.log" 2>&1 && grep -q 'up to date' "$C/status2.log" && ok || bad "status not clean after the update: $(sed 's/\x1b\[[0-9;]*m//g' "$C/status2.log" | grep '!' | head -1)"
}

git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1 || { echo "  not a git repo — upgrade matrix skipped"; echo; echo "  0 passed, 0 failed"; exit 0; }
for v in $VERSIONS; do
  n=${v%%:*}; c=${v##*:}
  if ! git -C "$ROOT" cat-file -e "$c^{commit}" 2>/dev/null; then echo "  $n ($c) not in this clone — skipped (shallow checkout?)"; continue; fi
  [ "$n" = "$NEW_VERSION" ] && continue
  mkdir -p "$W/kit-$n"; git -C "$ROOT" archive "$c" | tar -x -C "$W/kit-$n"
  for r in standalone hooks-from-plugin as-plugin; do
    printf '  %-6s %-18s' "$n" "$r"; p0=$pass; f0=$fail
    cell "$W/kit-$n" "$r" "$W/cell-$n-$r"
    printf '%s ok' "$((pass-p0))"; [ "$((fail-f0))" = 0 ] && printf '\n' || printf ', %s FAILED\n' "$((fail-f0))"
  done
done
echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
