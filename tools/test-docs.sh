#!/usr/bin/env bash
# Consistency check: does the documentation still describe the thing that exists?
#
#     tools/test-docs.sh
#
# This exists because the corpus this kit came from had, at audit, a README documenting a hook that
# was in no settings file and a memory whose central claim had flipped three times — each audit
# reasoning from the previous audit's prose. Documentation of a mechanism must be derived from the
# mechanism, and where it cannot be generated it must at least be VERIFIED. Hand-written numbers in
# particular rot within days: two were already stale when this check was written.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Knobs an adopted setup may set in settings.json reach a running session's tool environment.
# A suite that inherits them is not testing the shipped defaults.
unset RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_RECENT_N 2>/dev/null || true
W="${TMPDIR:-/tmp}/raememberit-docs.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; fail=$((fail+1)); }

echo "=== no stale vocabulary anywhere ==="
# starter/ is excluded: those are engineering rules whose prose legitimately uses words like "sibling"
# Literals are SPLIT so this file contains no token it searches for — the same reason the
# sanitization gate splits its probes. An exclusion would be a blind spot; a split is self-evident.
# grep --exclude-dir did not reliably prune .git here, so the file list is built explicitly.
git -C "$ROOT" ls-files > "$W/tracked" 2>/dev/null || find "$ROOT" -type f -not -path '*/.git/*' > "$W/tracked"
for pat in "mem""kit" "MEM""KIT_"; do
  h=$(cd "$ROOT" && tr '\n' '\0' < "$W/tracked" | xargs -0 grep -ln -- "$pat" 2>/dev/null || true)
  [ -z "$h" ] && ok "no '$pat' in any tracked file" || bad "'$pat' still present" "$h"
done

echo "=== the installed git hook matches its source ==="
# A string search would not have caught this: the stale installed hook differed from its source only
# in a comment, so the gate still ran and nothing looked wrong. Compare the files instead.
if [ ! -f "$ROOT/.git/hooks/pre-commit" ]; then
  ok "no git hook installed in this clone (run tools/install-hooks.sh)"
elif diff -q "$ROOT/.git/hooks/pre-commit" "$ROOT/tools/pre-commit" >/dev/null 2>&1; then
  ok ".git/hooks/pre-commit is current"
else
  bad ".git/hooks/pre-commit has drifted from tools/pre-commit — re-run tools/install-hooks.sh"
fi
for pat in "sibling of the ""config" "beside the ""config" "outside the ""config dir"; do
  h=$(cd "$ROOT" && grep -rln -- "$pat" . --exclude-dir=.git --exclude-dir=starter 2>/dev/null || true)
  [ -z "$h" ] && ok "no stale placement claim: '$pat'" || bad "stale placement claim '$pat'" "$h"
done

echo "=== the hook table is derived from the wiring, not typed ==="
bash "$ROOT/tools/gen-hook-table.sh" > "$W/gen" 2>/dev/null
sed -n '/^| Event | Matcher | Script | Timeout |/,/rebuild-index-hook/p' "$ROOT/docs/commands.md" > "$W/doc"
if diff -q "$W/gen" "$W/doc" >/dev/null 2>&1; then ok "docs/commands.md hook table matches engine/settings.fragment.json"
else bad "docs/commands.md hook table has drifted from the wiring" "$(diff "$W/gen" "$W/doc" | head -4)"; fi
# Every hook script the wiring names must be explained in the same page, by name.
for h in $(jq -r '.hooks[][].hooks[].command' "$ROOT/engine/settings.fragment.json" | sed 's|.*/||' | sort -u); do
  grep -q "\`$h\`" "$ROOT/docs/commands.md" && ok "docs/commands.md explains $h" || bad "docs/commands.md does not explain $h"
done

echo "=== every internal link in the docs resolves ==="
# A manual whose links rot is one people stop opening. Relative links only; anchors are checked
# loosely (the target file must exist; heading text is not verified).
broken=""
for f in "$ROOT/README.md" "$ROOT/docs"/*.md; do
  for l in $(grep -oE '\]\(([^)#]+)(#[^)]*)?\)' "$f" | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' | grep -vE '^(https?:|mailto:)' | sort -u); do
    [ -e "$(dirname "$f")/$l" ] || broken="$broken
  $(basename "$f") -> $l"
  done
done
[ -z "$broken" ] && ok "every relative link in README.md and docs/ points at a file that exists" || bad "broken links" "$broken"
for d in README.md getting-started.md how-it-works.md cadence.md commands.md configuration.md upgrading.md troubleshooting.md advanced.md development.md internals.md; do
  [ -f "$ROOT/docs/$d" ] && ok "docs/$d exists" || bad "docs/$d is missing"
done
grep -q '```mermaid' "$ROOT/README.md" && grep -q '```mermaid' "$ROOT/docs/how-it-works.md" && grep -q '```mermaid' "$ROOT/docs/cadence.md" \
  && ok "the README, how-it-works and cadence pages carry Mermaid diagrams" || bad "a Mermaid diagram is missing"

echo "=== the plugin's hooks are generated from the settings fragment, not typed twice ==="
# Two ways to wire the same hooks — a settings fragment the standalone installer merges, and the
# plugin's own hooks.json — is a drift surface. This project has been bitten three times by two
# descriptions of one mechanism diverging, so one is generated from the other and this asserts it.
if [ ! -f "$ROOT/plugin/hooks/hooks.json" ]; then
  bad "plugin/hooks/hooks.json is missing"
elif python3 - "$ROOT" <<'PYCHK'
import json, sys
root = sys.argv[1]
def graph(path, key="hooks"):
    d = json.load(open(path))[key]
    out = []
    for ev, groups in d.items():
        for g in groups:
            for h in g["hooks"]:
                out.append((ev, g.get("matcher", None), h["command"].rsplit("/hooks/", 1)[-1], h.get("timeout")))
    return sorted(out)
frag = graph(root + "/engine/settings.fragment.json")
plug = graph(root + "/plugin/hooks/hooks.json")
# The plugin adds exactly one hook the standalone install does not need: place-shim.sh, which gives
# the write helper a version-free path for the permission rule. A standalone install already has one.
extra = [e for e in plug if e not in frag]
missing = [e for e in frag if e not in plug]
sys.exit(0 if not missing and [e[2] for e in extra] == ["place-shim.sh"] else 1)
PYCHK
then
  ok "plugin hooks.json carries the same hooks as the fragment (+ place-shim only)"
else
  bad "plugin hooks.json has drifted — re-run tools/build-plugin.sh"
fi
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate "$ROOT/plugin" 2>&1 | grep -q "Validation passed"; then ok "plugin manifest validates"
  else bad "plugin manifest does not validate"; fi
else ok "claude CLI absent — manifest validation skipped"; fi

missing=""
for cmdstr in $(jq -r '.hooks[][].hooks[].command' "$ROOT/plugin/hooks/hooks.json" | sed 's|.*/hooks/||'); do
  [ -x "$ROOT/engine/hooks/$cmdstr" ] || missing="$missing $cmdstr"
done
if [ -z "$missing" ]; then ok "every hook script the plugin names exists and is executable"
else bad "plugin names hook scripts that are missing:$missing"; fi

echo "=== every protocol template is installable ==="
for f in "$ROOT/protocol"/*.md.tmpl; do
  b=$(basename "$f")
  grep -q '{{MEM}}' "$f" && ok "$b carries the corpus slot" || bad "$b has no {{MEM}} slot"
done
# the read-only commands must NOT claim to write; the writing ones must use the helper
for b in learn memory-reflect; do
  grep -q 'mem-write.sh' "$ROOT/protocol/$b.md.tmpl" \
    && ok "$b writes through the helper" || bad "$b does not mention the write helper"
done
grep -q 'mem-write.sh\|cat > ' "$ROOT/protocol/skill-mine.md.tmpl" \
  && ok "skill-mine writes over Bash (its output lands in a sensitive path too)" \
  || bad "skill-mine still implies the Write tool"

echo "=== every hook that needs the corpus resolves it through the shared lib ==="
for f in "$ROOT/engine/hooks"/*.sh; do
  b=$(basename "$f")
  needs=$(grep -c 'RAEMEMBERIT_MEM\b' "$f" || true)
  srcs=$(grep -c 'raememberit-root.sh' "$f" || true)
  if [ "$needs" -gt 0 ] && [ "$srcs" -eq 0 ]; then bad "$b uses the corpus path without sourcing the resolver"
  else ok "$b resolver use is consistent"; fi
done

echo "=== claimed numbers match measured ones ==="
A=$(bash "$ROOT/tools/test-sanitize-scan.sh" | tail -1 | awk '{print $1}')
B=$(bash "$ROOT/tools/test-dedup.sh"        | tail -1 | awk '{print $1}')
C=$(bash "$ROOT/tools/test-mem-write.sh"    | tail -1 | awk '{print $1}')
D=$(bash "$ROOT/tools/test-install.sh"      | tail -1 | awk '{print $1}')
E=$(bash "$ROOT/tools/test-plugin.sh"       | tail -1 | awk '{print $1}')
# Counted by hand, and that hand has been wrong: a suite added without a line here is invisible to
# the very check that exists to stop a stale number. Add yours.
F=$(bash "$ROOT/tools/test-tripwire.sh"     | tail -1 | awk '{print $1}')
G=$(bash "$ROOT/tools/test-context.sh"      | tail -1 | awk '{print $1}')
H=$(bash "$ROOT/tools/test-wizard.sh"       | tail -1 | awk '{print $1}')
TOT=$((A+B+C+D+E+F+G+H))
for f in README.md docs/development.md; do
  claimed=$(grep -oE '[0-9]+ (automated )?assertions' "$ROOT/$f" | head -1 | awk '{print $1}')
  if [ -z "$claimed" ]; then ok "$f claims no assertion count"
  elif [ "$claimed" = "$TOT" ]; then ok "$f assertion count is current ($TOT)"
  else bad "$f claims $claimed assertions; there are $TOT"; fi
done
N=$(ls "$ROOT/starter/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$N" -ge 8 ] && [ "$N" -le 12 ] && ok "starter set is $N rules, inside the stated 8-12 range" \
  || bad "starter set is $N rules, outside the stated 8-12 range"

echo "=== one version, and nothing restates it ==="
# The version WAS two literals: build-plugin.sh wrote the marketplace tree's manifest and
# gen-hooks-only-plugin.py wrote the one the installer produces. A bump to the first never reached a
# real install, and nothing compared them.
#
# Both now read VERSION, so asserting "generator agrees with VERSION" would be TAUTOLOGICAL — worse,
# test-plugin.sh runs build-plugin.sh in place, so by the time this runs the tree has already been
# resynced to whatever VERSION says. Assert the two things that can actually still be false:
#   1. a SECOND literal has been reintroduced somewhere
#   2. the COMMITTED manifest is behind VERSION, i.e. someone bumped without rebuilding
V=$(cat "$ROOT/VERSION" 2>/dev/null | tr -d ' \n')
[ -n "$V" ] && ok "VERSION is $V" || bad "no VERSION file at the repo root"

lits=$(grep -rnE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' \
        "$ROOT/tools" "$ROOT/install.sh" 2>/dev/null | grep -v 'test-plugin.sh' || true)
[ -z "$lits" ] && ok "no generator restates the version as a literal" \
                || bad "a second version literal has reappeared" "$lits"

CV=$(git -C "$ROOT" show HEAD:plugin/.claude-plugin/plugin.json 2>/dev/null \
     | python3 -c "import json,sys;print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
if [ -z "$CV" ]; then ok "no committed plugin manifest to compare (fresh clone)"
elif [ "$CV" = "$V" ]; then ok "committed plugin manifest is current ($CV)"
else bad "committed plugin manifest is $CV but VERSION is $V — bumped without rebuilding"; fi

echo "=== the frozen baseline still describes a fresh install ==="
T="$W/inst"
bash "$ROOT/install.sh" --config-dir "$T" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$T" python3 "$T/raememberit/engine/eval/run_eval.py" --json > "$W/now.json" 2>/dev/null
if python3 - "$W/now.json" "$ROOT/starter/baseline.json" > "$W/cmp" 2>&1 <<'PY'
import json,sys
now=json.load(open(sys.argv[1])); base=json.load(open(sys.argv[2]))
for st in ("literal","expanded"):
    n,b = now["runs"][st], base["runs"][st]
    assert (n["passed"],n["total"]) == (b["passed"],b["total"]), \
        f"{st}: now {n['passed']}/{n['total']}, baseline {b['passed']}/{b['total']}"
assert now["health"]["dup_pairs"] == 0, "starter corpus now contains near-duplicates"
assert now["health"]["dangling"] == 0, "starter corpus now has dangling wikilinks"
# A retrieval score describes a corpus the model may never have RECEIVED. If the shipped starter
# tier ever grew past the budget, every fresh install would be born unable to deliver it, and the
# scores above would keep reporting a corpus nobody ever saw.
assert now["delivery"]["delivered"] is base["delivery"]["delivered"], \
    f"delivery: now {now['delivery']['delivered']}, baseline {base['delivery']['delivered']}"
assert now["delivery"]["always_on_bytes"] < 8000, \
    f"starter always-on tier is {now['delivery']['always_on_bytes']} B, at or over the default budget"
print(f"literal {now['runs']['literal']['passed']}/{now['runs']['literal']['total']} · "
      f"expanded {now['runs']['expanded']['passed']}/{now['runs']['expanded']['total']} · "
      f"0 dupes · 0 dangling · delivered, {now['delivery']['always_on_bytes']} B always-on")
PY
then ok "baseline matches: $(cat "$W/cmp")"
else bad "baseline drift" "$(cat "$W/cmp" | tail -2)"; fi

echo "=== docs only reference paths that exist after an install ==="
for pth in raememberit/INSTRUCTIONS-fragment.md raememberit/engine/rebuild-index.sh \
           raememberit/engine/eval/run_eval.py raememberit/engine/mem-write.sh \
           raememberit/engine/find-similar.py; do
  [ -e "$T/$pth" ] && ok "installed: $pth" || bad "docs reference a path that is not installed: $pth"
done

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
