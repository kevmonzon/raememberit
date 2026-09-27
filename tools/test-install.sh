#!/usr/bin/env bash
# Test install.sh against a throwaway config dir: fresh install, then re-run.
#
#     tools/test-install.sh
#
# The re-run half is the point. An installer that is only tested once will duplicate hooks,
# clobber a colleague's own wiring, or overwrite memories the second time someone upgrades — and
# that second time is the one nobody watches.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="${TMPDIR:-/tmp}/memkit-install-test.$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T" "$(dirname "$T")/memkit-memory"' EXIT

pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
       else printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
ckt() { if eval "$2" >/dev/null 2>&1; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
        else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# The corpus is a SIBLING of the config dir (see engine/lib/memkit-root.sh for why), so the tests
# below look for memories there, not under the config dir.
MEM="$(dirname "$T")/memkit-memory"
rm -rf "$MEM"

# a pre-existing settings file with the colleague's OWN hook, which must survive
mkdir -p "$T"
cat > "$T/settings.json" <<'J'
{
  "theme": "dark",
  "hooks": {
    "SessionEnd": [{"matcher": "", "hooks": [{"type": "command", "command": "echo their-own-hook"}]}]
  }
}
J

echo "=== fresh install ==="
"$ROOT/install.sh" --config-dir "$T" --profile example --user Casey >"$T/log1" 2>&1
ck "installer exited 0" "$?" "0"
ckt "engine installed"              "[ -x '$T/memkit/engine/rebuild-index.sh' ]"
ck  "commands installed"            "$(ls "$T/commands" 2>/dev/null | wc -l | tr -d ' ')" "5"
ckt "indexes generated"             "[ -s '$MEM/MEMORY.md' ] && [ -s '$MEM/MEMORY-CATALOG.md' ]"
ckt "user_profile installed"        "[ -f '$MEM/user_profile.md' ]"
ckt "eval queries installed"        "[ -f '$MEM/eval/queries.json' ]"
ckt "instructions fragment written" "[ -s '$T/memkit/INSTRUCTIONS-fragment.md' ]"
ckt "profile persona appended"      "grep -q '## Voice' '$T/memkit/INSTRUCTIONS-fragment.md'"
ckt "profile vocabulary installed"  "[ -f '$T/memkit/vocabulary.txt' ]"

echo "=== the addressee slot ==="
ckt "no unfilled slots anywhere"    "bash '$ROOT/tools/check-filled.sh' '$T/commands'"
ckt "--user overrode the profile"   "grep -q 'Casey' '$T/commands/learn.md'"
ckt "profile default not used"      "! grep -q 'Alex' '$T/commands/learn.md'"

echo "=== starter corpus ==="
N=$(ls "$MEM/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
ckt "starter rules installed (got $N)" "[ '$N' -ge 11 ]"
ckt "profile's extra rule installed"   "[ -f '$MEM/feedback/plan-substantial-work-to-files.md' ]"
ckt "always-on index lists them"       "grep -q 'verify-effect-not-just-wiring' '$MEM/MEMORY.md'"

echo "=== corpus lives OUTSIDE the config dir, and writing it does not prompt ==="
ckt "corpus is a sibling, not inside .claude" "[ -d '$MEM/feedback' ] && [ ! -d '$T/memory/feedback' ]"
ckt "corpus path published as env"            "grep -q 'MEMKIT_MEMORY_DIR' '$T/settings.json'"
ckt "allow rule added for the corpus"         "grep -q 'Edit($MEM/\*\*)' '$T/settings.json'"

echo "=== hooks merged, not replaced ==="
ckt "their own hook survived"  "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their theme survived"     "grep -q '\"dark\"' '$T/settings.json'"
M=$(grep -c '/memkit/engine/hooks/' "$T/settings.json" | tr -d ' ')
ckt "memkit hooks wired (got $M)" "[ '$M' -ge 8 ]"

echo "=== retrieval actually works on the starter corpus ==="
CLAUDE_CONFIG_DIR="$T" MEMKIT_MEMORY_DIR="$MEM" python3 "$T/memkit/engine/eval/run_eval.py" --json > "$T/eval.json" 2>"$T/everr"
if python3 - "$T/eval.json" > "$T/evalsum" 2>&1 <<'PY2'
import json,sys
d=json.load(open(sys.argv[1]))
lit, exp = d["runs"]["literal"], d["runs"]["expanded"]
print(f"literal {lit['passed']}/{lit['total']} · expanded {exp['passed']}/{exp['total']} "
      f"(hit@1 {exp['hit1']}, hit@3 {exp['hit3']})")
# Every starter query must resolve under expansion. If one does not, either a starter rule's
# description stopped being a routing signal or a query was written against wording that is gone.
assert exp["passed"] == exp["total"], f"{exp['total']-exp['passed']} expanded query/queries failed"
# Expansion must be worth something, or step 1 of the recall command is ceremony.
assert exp["passed"] > lit["passed"], "expansion bought nothing over literal matching"
PY2
then printf '  ok    eval: %s\n' "$(cat "$T/evalsum")"; pass=$((pass+1))
else printf '  FAIL  eval on the starter corpus\n'; sed 's/^/          /' "$T/evalsum" | head -6; fail=$((fail+1)); fi

echo "=== a half-initialised corpus still gets its starter rules ==="
H="$T-half"; HM="$(dirname "$T")/memkit-memory-half"
rm -rf "$H" "$HM"; mkdir -p "$HM/feedback"
printf '# Memory Index\n' > "$HM/MEMORY.md"     # a generated index, not a memory
MEMKIT_MEMORY_DIR="$HM" "$ROOT/install.sh" --config-dir "$H" --profile default >"$H.log" 2>&1
NH=$(ls "$HM/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
ckt "generated index alone does not count as an existing corpus (got $NH rules)" "[ '$NH' -ge 11 ]"
rm -rf "$H" "$HM" "$H.log"

echo "=== RE-RUN (the half that matters) ==="
# a memory the colleague wrote themselves, which must not be touched
cat > "$MEM/feedback/their-own-rule.md" <<'M'
---
name: their-own-rule
description: A rule the user wrote themselves; the installer must never touch it.
metadata:
  type: feedback
---
Do not clobber me.
M
echo "custom" > "$MEM/user_profile.md"
BEFORE_HOOKS=$(grep -c '/memkit/engine/hooks/' "$T/settings.json" | tr -d ' ')

"$ROOT/install.sh" --config-dir "$T" --profile example --user Casey >"$T/log2" 2>&1
ck "re-run exited 0" "$?" "0"
AFTER_HOOKS=$(grep -c '/memkit/engine/hooks/' "$T/settings.json" | tr -d ' ')
ck  "hooks NOT duplicated on re-run" "$AFTER_HOOKS" "$BEFORE_HOOKS"
ckt "their own hook still there"     "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their own memory untouched"     "[ -f '$MEM/feedback/their-own-rule.md' ]"
ck  "their user_profile NOT overwritten" "$(cat "$MEM/user_profile.md")" "custom"
ckt "re-run reported leaving the corpus alone" "grep -qi 'left completely alone' '$T/log2'"

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "--- fresh install log ---"; tail -25 "$T/log1"; exit 1; }
