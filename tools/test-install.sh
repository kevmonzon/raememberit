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
T="${TMPDIR:-/tmp}/raememberit-install-test.$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T" "$(dirname "$T")/raememberit-memory"' EXIT

pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
       else printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
ckt() { if eval "$2" >/dev/null 2>&1; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
        else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# The corpus is a SIBLING of the config dir (see engine/lib/raememberit-root.sh for why), so the tests
# below look for memories there, not under the config dir.
MEM="$(dirname "$T")/raememberit-memory"
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
ckt "engine installed"              "[ -x '$T/raememberit/engine/rebuild-index.sh' ]"
ck  "commands installed"            "$(ls "$T/commands" 2>/dev/null | wc -l | tr -d ' ')" "5"
ckt "indexes generated"             "[ -s '$MEM/MEMORY.md' ] && [ -s '$MEM/MEMORY-CATALOG.md' ]"
ckt "user_profile installed"        "[ -f '$MEM/user_profile.md' ]"
ckt "eval queries installed"        "[ -f '$MEM/eval/queries.json' ]"
ckt "instructions fragment written" "[ -s '$T/raememberit/INSTRUCTIONS-fragment.md' ]"
ckt "profile persona appended"      "grep -q '## Voice' '$T/raememberit/INSTRUCTIONS-fragment.md'"
ckt "profile vocabulary installed"  "[ -f '$T/raememberit/vocabulary.txt' ]"

echo "=== the addressee slot ==="
ckt "no unfilled slots anywhere"    "bash '$ROOT/tools/check-filled.sh' '$T/commands'"
ckt "--user overrode the profile"   "grep -q 'Casey' '$T/commands/learn.md'"
ckt "profile default not used"      "! grep -q 'Alex' '$T/commands/learn.md'"

echo "=== starter corpus ==="
N=$(ls "$MEM/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
ckt "starter rules installed (got $N)" "[ '$N' -ge 11 ]"
ckt "profile's extra rule installed"   "[ -f '$MEM/feedback/plan-substantial-work-to-files.md' ]"
ckt "always-on index lists them"       "grep -q 'verify-effect-not-just-wiring' '$MEM/MEMORY.md'"

echo "=== installed commands point at the REAL corpus (doc/code drift guard) ==="
# This assertion exists because the corpus moved once and the command templates did not follow. A
# live session then reported a confident "no prior memory" after grepping a directory that does not
# exist. Documentation of a path must be derived from the path.
ckt "commands name the resolved corpus"        "grep -q 'MEM=\"$MEM\"' '$T/commands/recall.md'"
ckt "commands do NOT re-derive the corpus path" "! grep -q 'CLAUDE_CONFIG_DIR:-\$HOME/.claude}/memory' '$T/commands/recall.md'"
NMEM=$(grep -l "MEM=\"$MEM\"" "$T/commands"/*.md 2>/dev/null | wc -l | tr -d ' ')
ck  "every command got the corpus path" "$NMEM" "5"

echo "=== corpus lives OUTSIDE the config dir, and writing it does not prompt ==="
ckt "corpus is a sibling, not inside .claude" "[ -d '$MEM/feedback' ] && [ ! -d '$T/memory/feedback' ]"
ckt "corpus path published as env"            "grep -q 'RAEMEMBERIT_MEMORY_DIR' '$T/settings.json'"
ckt "allow rule added for the corpus"         "grep -q 'Edit($MEM/\*\*)' '$T/settings.json'"

echo "=== hooks merged, not replaced ==="
ckt "their own hook survived"  "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their theme survived"     "grep -q '\"dark\"' '$T/settings.json'"
M=$(grep -c '/raememberit/engine/hooks/' "$T/settings.json" | tr -d ' ')
ckt "raememberit hooks wired (got $M)" "[ '$M' -ge 8 ]"

echo "=== retrieval actually works on the starter corpus ==="
CLAUDE_CONFIG_DIR="$T" RAEMEMBERIT_MEMORY_DIR="$MEM" python3 "$T/raememberit/engine/eval/run_eval.py" --json > "$T/eval.json" 2>"$T/everr"
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
H="$T-half"; HM="$(dirname "$T")/raememberit-memory-half"
rm -rf "$H" "$HM"; mkdir -p "$HM/feedback"
printf '# Memory Index\n' > "$HM/MEMORY.md"     # a generated index, not a memory
RAEMEMBERIT_MEMORY_DIR="$HM" "$ROOT/install.sh" --config-dir "$H" --profile default >"$H.log" 2>&1
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
BEFORE_HOOKS=$(grep -c '/raememberit/engine/hooks/' "$T/settings.json" | tr -d ' ')

"$ROOT/install.sh" --config-dir "$T" --profile example --user Casey >"$T/log2" 2>&1
ck "re-run exited 0" "$?" "0"
AFTER_HOOKS=$(grep -c '/raememberit/engine/hooks/' "$T/settings.json" | tr -d ' ')
ck  "hooks NOT duplicated on re-run" "$AFTER_HOOKS" "$BEFORE_HOOKS"
ckt "their own hook still there"     "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their own memory untouched"     "[ -f '$MEM/feedback/their-own-rule.md' ]"
ck  "their user_profile NOT overwritten" "$(cat "$MEM/user_profile.md")" "custom"
ckt "re-run reported leaving the corpus alone" "grep -qi 'left completely alone' '$T/log2'"

echo "=== UNINSTALL leaves their setup as it was, and keeps their memories ==="
"$ROOT/uninstall.sh" --config-dir "$T" >"$T/unlog" 2>&1
ck  "uninstall exited 0" "$?" "0"
ck  "commands removed"   "$(ls "$T/commands" 2>/dev/null | wc -l | tr -d ' ')" "0"
ckt "engine removed"     "[ ! -d '$T/raememberit' ]"
ckt "their own hook survived uninstall" "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their theme survived uninstall"    "grep -q '\"dark\"' '$T/settings.json'"
ckt "no leftover hook entries"          "! grep -q '/raememberit/engine/hooks/' '$T/settings.json'"
ckt "no leftover permission rules"      "! grep -q 'raememberit-memory' '$T/settings.json'"
ckt "MEMORIES KEPT by default"          "[ -f '$MEM/feedback/their-own-rule.md' ]"
ckt "uninstall said so"                 "grep -qi 'KEPT' '$T/unlog'"

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "--- fresh install log ---"; tail -25 "$T/log1"; exit 1; }
