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

# Knobs an adopted setup may set in settings.json reach a running session's tool environment.
# A suite that inherits them is not testing the shipped defaults.
unset RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_RECENT_N 2>/dev/null || true
T="${TMPDIR:-/tmp}/raememberit-install-test.$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T" "$W_PERSONA" "$W_VOCAB"' EXIT

pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
       else printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
ckt() { if eval "$2" >/dev/null 2>&1; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
        else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# The corpus lives INSIDE the config dir, so the whole directory stays one portable unit. Writes get
# there through engine/mem-write.sh over Bash, because the Edit/Write tools refuse paths inside a
# `.claude` directory. See engine/lib/raememberit-root.sh.
W_PERSONA="${TMPDIR:-/tmp}/rmb-test-persona.$$"; printf '## Voice\n\nTerse.\n' > "$W_PERSONA"
W_VOCAB="${TMPDIR:-/tmp}/rmb-test-vocab.$$";   printf 'auth, login, sso\n'   > "$W_VOCAB"
MEM="$T/memory"

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
"$ROOT/install.sh" --config-dir "$T" --user Casey --persona "$W_PERSONA" --vocabulary "$W_VOCAB" >"$T/log1" 2>&1
ck "installer exited 0" "$?" "0"
ckt "engine installed"              "[ -x '$T/raememberit/engine/rebuild-index.sh' ]"
ck  "commands installed"            "$(ls "$T/commands" 2>/dev/null | wc -l | tr -d ' ')" "5"
ckt "indexes generated"             "[ -s '$MEM/MEMORY.md' ] && [ -s '$MEM/MEMORY-CATALOG.md' ]"
ckt "user_profile installed"        "[ -f '$MEM/user_profile.md' ]"
ckt "eval queries installed"        "[ -f '$MEM/eval/queries.json' ]"
ckt "instructions fragment written" "[ -s '$T/raememberit/INSTRUCTIONS-fragment.md' ]"
ckt "--persona is appended to the fragment" "grep -q 'Terse.' '$T/raememberit/INSTRUCTIONS-fragment.md'"
ckt "--vocabulary is installed"     "[ -f '$T/raememberit/vocabulary.txt' ]"

echo "=== the addressee slot ==="
ckt "no unfilled slots anywhere"    "bash '$ROOT/tools/check-filled.sh' '$T/commands'"
ckt "--user reaches the commands"   "grep -q 'Casey' '$T/commands/learn.md'"
ckt "no stray default addressee"    "! grep -q '{{USER}}' '$T/commands/learn.md'"

echo "=== starter corpus ==="
N=$(ls "$MEM/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
ck  "exactly the 11 starter rules" "$N" "11"
ckt "optional rules are NOT installed" "[ ! -f '$MEM/feedback/plan-substantial-work-to-files.md' ]"
ckt "always-on index lists them"       "grep -q 'verify-effect-not-just-wiring' '$MEM/MEMORY.md'"

echo "=== installed commands point at the REAL corpus (doc/code drift guard) ==="
# This assertion exists because the corpus moved once and the command templates did not follow. A
# live session then reported a confident "no prior memory" after grepping a directory that does not
# exist. Documentation of a path must be derived from the path.
ckt "commands name the resolved corpus"        "grep -q 'MEM=\"$MEM\"' '$T/commands/recall.md'"
ckt "commands do NOT re-derive the corpus path" "! grep -q 'CLAUDE_CONFIG_DIR:-\$HOME/.claude}/memory' '$T/commands/recall.md'"
NMEM=$(grep -l "MEM=\"$MEM\"" "$T/commands"/*.md 2>/dev/null | wc -l | tr -d ' ')
ck  "every command got the corpus path" "$NMEM" "5"

echo "=== corpus lives INSIDE the config dir; the WRITE HELPER is what is permitted ==="
ckt "corpus is inside the config dir"   "[ -d '$T/memory/feedback' ]"
ckt "no stray sibling directory"        "[ ! -d '$(dirname "$T")/raememberit-memory' ]"
ckt "corpus path published as env"      "grep -q 'RAEMEMBERIT_MEMORY_DIR' '$T/settings.json'"
ckt "write helper is allow-listed"      "grep -q 'Bash(.*mem-write.sh' '$T/settings.json'"
# An Edit() rule inside a .claude path is refused by the sensitive-file gate no matter what it says,
# so promising one would be a lie the installer tells the user.
ckt "no misleading Edit() rule on the corpus" "! grep -q 'Edit(.*/memory/' '$T/settings.json'"
ckt "the helper actually writes"        "printf -- '---\nname: probe-note\ndescription: A probe memory written through the helper during the test suite\nmetadata:\n  type: reference\n---\n\nbody\n' | CLAUDE_CONFIG_DIR='$T' bash '$T/raememberit/engine/mem-write.sh' reference probe-note"
ckt "and it lands in the catalog"       "grep -q 'probe-note' '$MEM/MEMORY-CATALOG.md'"

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
H="$T-half"; rm -rf "$H"; mkdir -p "$H/memory/feedback"
printf '# Memory Index\n' > "$H/memory/MEMORY.md"     # a generated index, not a memory
"$ROOT/install.sh" --config-dir "$H"  >"$H.log" 2>&1
NH=$(ls "$H/memory/feedback"/*.md 2>/dev/null | wc -l | tr -d ' ')
ckt "generated index alone does not count as an existing corpus (got $NH rules)" "[ '$NH' -ge 11 ]"
rm -rf "$H" "$H.log"

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

"$ROOT/install.sh" --config-dir "$T" --user Casey --persona "$W_PERSONA" --vocabulary "$W_VOCAB" >"$T/log2" 2>&1
ck "re-run exited 0" "$?" "0"
AFTER_HOOKS=$(grep -c '/raememberit/engine/hooks/' "$T/settings.json" | tr -d ' ')
ck  "hooks NOT duplicated on re-run" "$AFTER_HOOKS" "$BEFORE_HOOKS"
ckt "their own hook still there"     "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their own memory untouched"     "[ -f '$MEM/feedback/their-own-rule.md' ]"
ck  "their user_profile NOT overwritten" "$(cat "$MEM/user_profile.md")" "custom"
ckt "re-run reported leaving the corpus alone" "grep -qi 'left completely alone' '$T/log2'"

echo "=== a command YOU edited is never overwritten by a re-install ==="
# This is the one failure mode that would silently destroy work: adopting the kit into an existing
# setup means the command text may legitimately be yours.
MAN="$T/raememberit/.installed-commands"
ckt "install recorded a manifest"  "[ -s '$MAN' ]"
printf '\n<!-- local edit that must survive -->\n' >> "$T/commands/learn.md"
EDITED=$(shasum "$T/commands/learn.md" | cut -d' ' -f1)
"$ROOT/install.sh" --config-dir "$T" --user Casey --persona "$W_PERSONA" --vocabulary "$W_VOCAB" >"$T/log3" 2>&1
ck  "edited command untouched" "$(shasum "$T/commands/learn.md" | cut -d' ' -f1)" "$EDITED"
ckt "and it said so"                    "grep -q 'YOU edited this' '$T/log3'"
ckt "the shipped version is saved for comparison" "[ -f '$T/raememberit/shipped/learn.md' ]"
ckt "the diff hint it printed is runnable"        "grep -qE 'diff .+/shipped/learn.md .+/commands/learn.md' '$T/log3'"
ckt "the other four were not skipped"             "grep -q '1 left alone' '$T/log3'"
# and the escape hatch works, but only when asked for explicitly
"$ROOT/install.sh" --config-dir "$T" --user Casey --persona "$W_PERSONA" --vocabulary "$W_VOCAB" --force-commands >"$T/log4" 2>&1
ckt "--force-commands overwrites it"    "! grep -q 'local edit that must survive' '$T/commands/learn.md'"
ckt "and says it is doing so"           "grep -q 'force-commands given' '$T/log4'"

echo "=== guided mode: onboards, warns about predecessor hooks, never hangs ==="
# The predecessor-hook warning is the highest-value thing guided mode does: adopting this into a setup
# that already has memory hooks doubles everything, and the installer cannot safely remove them.
G="$T-guided"; rm -rf "$G"; mkdir -p "$G"
cat > "$G/settings.json" <<'J'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"cat ~/.claude/memory/MEMORY.md"}]}],
          "SessionEnd":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/memory/rebuild-index.sh"}]}]}}
J
"$ROOT/install.sh" --config-dir "$G"  --guided >"$G.log" 2>&1
ck  "guided install exits 0 without a terminal" "$?" "0"
ckt "warns about predecessor hooks"             "grep -q 'memory hooks of your own on' '$G.log'"
ckt "names the events it found"                 "grep -qE 'own on:.*(UserPromptSubmit|SessionEnd)' '$G.log'"
ckt "explains the consequence, not just the fact" "grep -q 'injected twice' '$G.log'"
ckt "walks the first loop"                      "grep -q 'first loop' '$G.log'"
ckt "says how to get out"                       "grep -q 'uninstall.sh' '$G.log'"
ckt "explains the session-end reminder"         "grep -q 'RAEMEMBERIT_REQUIRE_LOG=strict' '$G.log'"
ckt "does NOT write to any CLAUDE.md unasked"   "! test -f '$G/CLAUDE.md'"

G2="$T-guided-clean"; rm -rf "$G2"
"$ROOT/install.sh" --config-dir "$G2"  --guided >"$G2.log" 2>&1
ckt "clean config gets no predecessor warning"  "grep -q 'no memory hooks of your own' '$G2.log'"

# a re-run must not re-onboard someone who has already been onboarded
"$ROOT/install.sh" --config-dir "$G2"  >"$G2.log2" 2>&1
ckt "a plain re-run stays terse"                "! grep -q 'first loop' '$G2.log2'"
rm -rf "$G" "$G2" "$G.log" "$G2.log" "$G2.log2"

echo "=== UNINSTALL leaves their setup as it was, and keeps their memories ==="
"$ROOT/uninstall.sh" --config-dir "$T" >"$T/unlog" 2>&1
ck  "uninstall exited 0" "$?" "0"
ck  "commands removed"   "$(ls "$T/commands" 2>/dev/null | wc -l | tr -d ' ')" "0"
ckt "engine removed"     "[ ! -d '$T/raememberit' ]"
ckt "their own hook survived uninstall" "grep -q 'their-own-hook' '$T/settings.json'"
ckt "their theme survived uninstall"    "grep -q '\"dark\"' '$T/settings.json'"
ckt "no leftover hook entries"          "! grep -q '/raememberit/engine/hooks/' '$T/settings.json'"
ckt "no leftover permission rules"      "! grep -q 'raememberit' '$T/settings.json'"
ckt "the corpus directory itself survives" "[ -d '$MEM/feedback' ]"
ckt "MEMORIES KEPT by default"          "[ -f '$MEM/feedback/their-own-rule.md' ]"
ckt "uninstall said so"                 "grep -qi 'KEPT' '$T/unlog'"

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "--- fresh install log ---"; tail -25 "$T/log1"; exit 1; }
