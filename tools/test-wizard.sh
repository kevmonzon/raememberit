#!/usr/bin/env bash
# The front door: `./raememberit install|update|status|uninstall` for someone who does not know
# what a hook is.
#
#     tools/test-wizard.sh
#
# Two things are asserted that the other suites cannot: that the happy path never shows a word from
# the jargon list (the whole point of the front door), and that with nobody present it takes every
# default and finishes — a wizard that hangs in CI is a wizard nobody trusts.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
unset RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_RECENT_N RAEMEMBERIT_USER 2>/dev/null || true
W="${TMPDIR:-/tmp}/raememberit-wizard.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; fail=$((fail+1)); }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
# Words a non-technical person should never meet on the happy path. Paths are exempt (a path is a
# place, not a concept), so lines that are only a path are dropped before the check.
JARGON='hook|corpus|plugin|manifest|json|scaffold|fragment|settings|permission|--force|--replace|--hooks-from|--as-plugin|CLAUDE_CONFIG_DIR|skills-dir|env |guided|addressee'
no_jargon() {  # $1 label, $2 file  — lines that are a path, or the boxed note itself, are exempt
  local hits; hits=$(strip < "$2" | grep -viE '^\s*(/|~|│|┌|└)' | grep -iE "$JARGON" || true)   # a path is a place, not a concept
  [ -z "$hits" ] && ok "$1: no jargon on the happy path" || bad "$1: jargon leaked" "$hits"
}
T="$W/.claude"; MEM="$T/memory"; WIZ="$ROOT/raememberit"

echo "=== no verb, bad verb, help ==="
bash "$WIZ" >"$W/o0" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q 'install' "$W/o0" && ok "no verb prints the four verbs and exits 2" || bad "no verb: rc=$rc"
bash "$WIZ" --help >"$W/o0" 2>&1 && grep -q 'uninstall' "$W/o0" && ok "--help works" || bad "--help failed"
bash "$WIZ" frobnicate >"$W/o0" 2>&1; [ $? = 2 ] && ok "an unknown word is refused with exit 2" || bad "unknown verb accepted"

echo "=== install, with nobody present ==="
bash "$WIZ" install --config-dir "$T" --name Casey </dev/null >"$W/o1" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "install finishes without a terminal (exit 0)" || bad "install rc=$rc" "$(tail -5 "$W/o1")"
[ -x "$T/raememberit/engine/mem-write.sh" ] && ok "the tools are in place" || bad "no engine installed"
[ -f "$T/skills/raememberit/hooks/hooks.json" ] && ok "the recommended route was chosen without asking" || bad "no hooks plugin — wrong route"
[ "$(ls "$MEM/feedback"/*.md | wc -l | tr -d ' ')" = 11 ] && ok "11 starter rules seeded" || bad "starter rules missing"
grep -q 'Here is what I will do' "$W/o1" && ok "it says what it will do before doing it" || bad "no preview"
grep -q 'starter rules to begin with' "$W/o1" && ok "the summary counts starter rules, not files" || bad "summary wording wrong"
grep -q 'background reminders in place' "$W/o1" && ok "reminders are mentioned in one line" || bad "reminders not mentioned"
grep -q '/recall tail exit code' "$W/o1" && ok "it ends with the two-minute try-it" || bad "no try-it"
grep -q 'user=Casey' "$T/raememberit/.config" && ok "--name reaches the install" || bad "name not recorded"
no_jargon "install" "$W/o1"

echo "=== the note in CLAUDE.md ==="
grep -q 'creating it' "$W/o1" && ok "it says the file will be created when it does not exist" || bad "no creation notice"
[ -f "$T/CLAUDE.md" ] && ok "CLAUDE.md was created" || bad "CLAUDE.md not created"
grep -q 'raememberit:begin' "$T/CLAUDE.md" && grep -q 'raememberit:end' "$T/CLAUDE.md" && ok "the note sits between markers" || bad "markers missing"
IMP=$(sed -n 's/^@//p' "$T/CLAUDE.md" | head -1)
[ -n "$IMP" ] && [ -f "$IMP" ] && ok "the @ line imports a file that exists" || bad "@ line points nowhere: $IMP"
! grep -q '<config>' "$IMP" && ok "the imported explanation has real paths, not <config>" || bad "placeholder left in the fragment"
grep -q "$T/raememberit/engine/mem-write.sh" "$IMP" && ok "and it names the real write helper path" || bad "fragment does not name the real helper path"
grep -q 'added — Claude will now use memories' "$W/o1" && ok "the summary confirms the note" || bad "note not confirmed"
# A CLAUDE.md that already speaks of memories in the person's own words is left alone.
T2="$W/own/.claude"; mkdir -p "$T2"; printf '# Mine\n\nRun /recall before digging.\n' > "$T2/CLAUDE.md"
bash "$WIZ" install --config-dir "$T2" --yes >"$W/own.log" 2>&1
grep -q 'already tells Claude about memories' "$W/own.log" && ! grep -q 'raememberit:begin' "$T2/CLAUDE.md" \
  && ok "own-words instructions are respected, nothing appended" || bad "appended to a CLAUDE.md that already instructs"
# A CLAUDE.md about something else gets the note appended after its content, intact.
T3="$W/other/.claude"; mkdir -p "$T3"; printf '# Project notes\n\nUse tabs.\n' > "$T3/CLAUDE.md"
bash "$WIZ" install --config-dir "$T3" --yes >"$W/other.log" 2>&1
head -1 "$T3/CLAUDE.md" | grep -q '# Project notes' && grep -q 'Use tabs.' "$T3/CLAUDE.md" && grep -q 'raememberit:begin' "$T3/CLAUDE.md" \
  && ok "an unrelated CLAUDE.md keeps its content and gains the note" || bad "unrelated CLAUDE.md mishandled"
bash "$WIZ" uninstall --config-dir "$T3" --yes >"$W/other-un.log" 2>&1
! grep -q 'raememberit' "$T3/CLAUDE.md" && grep -q 'Use tabs.' "$T3/CLAUDE.md" && ok "uninstall removes exactly the note and keeps the rest" || bad "uninstall damaged CLAUDE.md" "$(cat "$T3/CLAUDE.md")"
grep -q 'the rest of the file is as it was' "$W/other-un.log" && ok "and says so" || bad "uninstall silent about the note"
rm -rf "$W/own" "$W/other"

echo "=== status on a fresh, current install ==="
bash "$WIZ" status --config-dir "$T" >"$W/o2" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "status exits 0 when current" || bad "status rc=$rc" "$(cat "$W/o2")"
grep -q 'up to date' "$W/o2" && ok "status says up to date" || bad "status does not say up to date"
grep -q 'background reminders in place' "$W/o2" && ok "status sees the reminders" || bad "status misses the reminders" "$(cat "$W/o2")"
grep -q 'Claude can save memories without asking' "$W/o2" && ok "status sees the write permission" || bad "status misses the permission"
! grep -q 'edited versions' "$W/o2" && ok "fresh commands are not reported as edited" || bad "fresh commands reported as edited"
no_jargon "status" "$W/o2"

echo "=== update from a newer download ==="
K="$W/newer"; mkdir -p "$K"
for x in raememberit install.sh uninstall.sh VERSION engine protocol tools starter scaffold; do cp -R "$ROOT/$x" "$K/"; done
printf '9.9.9\n' > "$K/VERSION"; printf '\n# newer\n' >> "$K/engine/hooks/close-log.sh"
printf '\n<!-- my edit -->\n' >> "$T/commands/learn.md"                     # the person edited a command
printf '\n# my patch\n' >> "$T/raememberit/engine/hooks/require-log.sh"     # and patched a tool
bash "$K/raememberit" status --config-dir "$T" >"$W/o3" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'run:  ./raememberit update' "$W/o3" && ok "status exits 1 and names the update when a newer download exists" || bad "status did not flag the newer download" "$(cat "$W/o3")"
grep -q '1 memory commands are your own' "$W/o3" && ok "status counts the edited command" || bad "edited command not counted" "$(cat "$W/o3")"
bash "$K/raememberit" update --config-dir "$T" </dev/null >"$W/o4" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "update finishes without a terminal" || bad "update rc=$rc" "$(tail -5 "$W/o4")"
grep -q 'this download is 9.9.9' "$W/o4" && ok "it names the version it brings" || bad "version not named"
grep -q 'edited 1 of the memory commands' "$W/o4" && ok "it warns about the edited command before acting" || bad "no edited-command warning"
grep -q 'you changed some of the background tools yourself (require-log.sh' "$W/o4" && ok "it names the tool the person patched" || bad "patched tool not named" "$(cat "$W/o4")"
grep -q 'old version is kept at' "$W/o4" && [ -d "$T/raememberit/engine.prev" ] && ok "and keeps the old version, saying where" || bad "old version not kept"
grep -q 'my edit' "$T/commands/learn.md" && ok "the edited command survived" || bad "edited command overwritten"
grep -q '# newer' "$T/raememberit/engine/hooks/close-log.sh" && ok "the tools were actually updated" || bad "tools not updated"
grep -q 'tools updated to 9.9.9' "$W/o4" && ok "the summary states the new version" || bad "summary missing"
no_jargon "update" "$W/o4"
bash "$K/raememberit" update --config-dir "$T" </dev/null >"$W/o5" 2>&1
grep -q 'nothing to update' "$W/o5" && ok "a second update says there is nothing to do" || bad "second update did not short-circuit"
rm -rf "$K"

echo "=== uninstall keeps the memories unless the phrase is typed ==="
N=$(find "$MEM/feedback" -name '*.md' | wc -l | tr -d ' ')
bash "$WIZ" uninstall --config-dir "$T" </dev/null >"$W/o6" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'Nothing was changed' "$W/o6" && [ -d "$T/raememberit" ] \
  && ok "without --yes and without a person, uninstall defaults to NO and changes nothing" || bad "uninstall proceeded by default"
bash "$WIZ" uninstall --yes --config-dir "$T" >"$W/o7" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "uninstall --yes finishes" || bad "uninstall rc=$rc" "$(cat "$W/o7")"
[ ! -d "$T/raememberit" ] && [ ! -d "$T/skills/raememberit" ] && ok "tools and reminders are gone" || bad "tools remain"
[ "$(find "$MEM/feedback" -name '*.md' | wc -l | tr -d ' ')" = "$N" ] && ok "memories kept ($N)" || bad "memories touched"
grep -q 'memories kept' "$W/o7" && grep -q 'delete my memories' "$W/o7" && ok "it says the memories stayed and how to delete them" || bad "uninstall summary wrong"
[ ! -f "$T/CLAUDE.md" ] && grep -q 'held nothing else, so it is gone too' "$W/o7" && ok "a CLAUDE.md that held only our note is removed with it" || bad "empty CLAUDE.md left behind"
no_jargon "uninstall" "$W/o7"
bash "$WIZ" install --config-dir "$T" --yes >/dev/null 2>&1
printf 'nope\n' | bash "$WIZ" uninstall --yes --and-my-memories --config-dir "$T" >"$W/o8" 2>&1
[ -d "$MEM/feedback" ] && grep -q 'that was not the phrase' "$W/o8" && ok "--and-my-memories with the wrong phrase keeps them" || bad "wrong phrase deleted memories"
bash "$WIZ" install --config-dir "$T" --yes >/dev/null 2>&1
printf 'delete my memories\n' | bash "$WIZ" uninstall --yes --and-my-memories --config-dir "$T" >"$W/o9" 2>&1
[ ! -d "$MEM" ] && grep -q 'memories deleted' "$W/o9" && ok "the exact phrase deletes them" || bad "phrase did not delete"
bash "$WIZ" uninstall --yes --config-dir "$T" >"$W/o10" 2>&1
grep -q 'nothing to remove' "$W/o10" && ok "uninstalling twice is harmless" || bad "second uninstall misbehaved" "$(cat "$W/o10")"

echo "=== --advanced hands everything to the old scripts unchanged ==="
bash "$WIZ" install --advanced --help >"$W/o11" 2>&1 && grep -q -- '--hooks-from-plugin' "$W/o11" && ok "install --advanced --help is install.sh's help" || bad "--advanced did not reach install.sh"
bash "$WIZ" uninstall --advanced --help >"$W/o12" 2>&1 && grep -q -- '--purge' "$W/o12" && ok "uninstall --advanced --help is uninstall.sh's help" || bad "--advanced did not reach uninstall.sh"

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
