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
sed -n '/^| Event | Matcher | Script | Timeout |/,/rebuild-index-hook/p' "$ROOT/README.md" > "$W/doc"
if diff -q "$W/gen" "$W/doc" >/dev/null 2>&1; then ok "README hook table matches engine/settings.fragment.json"
else bad "README hook table has drifted from the wiring" "$(diff "$W/gen" "$W/doc" | head -4)"; fi

echo "=== the plugin's hooks are generated from the settings fragment, not typed twice ==="
# Two ways to wire the same hooks — a settings fragment the standalone installer merges, and the
# plugin's own hooks.json — is a drift surface. This project has been bitten three times by two
# descriptions of one mechanism diverging, so one is generated from the other and this asserts it.
if [ ! -f "$ROOT/plugin/hooks/hooks.json" ]; then
  bad "plugin/hooks/hooks.json is missing"
elif diff -q <(jq -S '.hooks' "$ROOT/engine/settings.fragment.json") \
              <(jq -S '.hooks' "$ROOT/plugin/hooks/hooks.json") >/dev/null 2>&1; then
  ok "plugin hooks.json matches engine/settings.fragment.json"
else
  bad "plugin hooks.json has drifted — re-run tools/gen-plugin-hooks.sh"
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
TOT=$((A+B+C+D))
for f in README.md docs/PILOT.md; do
  claimed=$(grep -oE '[0-9]+ (automated )?assertions' "$ROOT/$f" | head -1 | awk '{print $1}')
  if [ -z "$claimed" ]; then ok "$f claims no assertion count"
  elif [ "$claimed" = "$TOT" ]; then ok "$f assertion count is current ($TOT)"
  else bad "$f claims $claimed assertions; there are $TOT"; fi
done
N=$(ls "$ROOT/starter/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$N" -ge 8 ] && [ "$N" -le 12 ] && ok "starter set is $N rules, inside the stated 8-12 range" \
  || bad "starter set is $N rules, outside the stated 8-12 range"

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
print(f"literal {now['runs']['literal']['passed']}/{now['runs']['literal']['total']} · "
      f"expanded {now['runs']['expanded']['passed']}/{now['runs']['expanded']['total']} · "
      f"0 dupes · 0 dangling")
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
