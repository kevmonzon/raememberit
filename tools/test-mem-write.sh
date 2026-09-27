#!/usr/bin/env bash
# Test engine/mem-write.sh — the write path, and the only place the schema is enforced.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${TMPDIR:-/tmp}/raememberit-memwrite.$$"
export CLAUDE_CONFIG_DIR="$W"

# A test of a DEFAULT must not inherit that setting from the environment. An adopted setup sets
# RAEMEMBERIT_DUPES in settings.json, and Claude Code puts settings env into the tool environment of
# a running session — so these assertions silently stopped testing the default and started confirming
# the ambient value. Unset every knob this suite exercises, explicitly.
unset RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_RECENT_N 2>/dev/null || true
mkdir -p "$W/memory"/{feedback,project,reference,interactions,eval}
trap 'rm -rf "$W"' EXIT
MW="$ROOT/engine/mem-write.sh"

pass=0; fail=0
ck() { local n="$1" e="$2"; shift 2
  "$@" >"$W/out" 2>&1; local a=$?
  if [ "$a" = "$e" ]; then printf '  ok    %s\n' "$n"; pass=$((pass+1))
  else printf '  FAIL  %s (expected exit %s, got %s)\n' "$n" "$e" "$a"
       sed 's/^/          /' "$W/out" | head -5; fail=$((fail+1)); fi; }
ckt() { if eval "$2" >/dev/null 2>&1; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
        else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
# value comparison, as opposed to ck() which RUNS a command — conflating the two is how three
# assertions in this file reported exit 127 instead of testing anything
cmp_() { if [ "$2" = "$3" ]; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
         else printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }

good() { cat <<EOF
---
name: $1
description: $2
metadata:
  type: $3
---

The fact, stated so it is actionable later.

**Why:** a test fixture.
**How to apply:** it is a fixture.
EOF
}

echo "=== a well-formed memory is written ==="
good trust-the-file "Read the live file rather than a memory describing it, every time" feedback \
  | "$MW" feedback trust-the-file >"$W/o1" 2>&1
cmp_ "exit 0" "$?" "0"
ckt "file landed"               "[ -f '$W/memory/feedback/trust-the-file.md' ]"
ckt "index was rebuilt"         "grep -q 'trust-the-file' '$W/memory/MEMORY.md'"

echo "=== the schema is ENFORCED, not requested ==="
printf -- '---\nname: trust-the-file\nmetadata:\n  type: feedback\n---\nbody\n' \
  > "$W/nodesc"; ck "no description is rejected" 1 sh -c "'$MW' feedback nodesc-slug < '$W/nodesc'"
good other-slug "A description that is comfortably long enough to pass the length check" feedback \
  > "$W/mismatch"; ck "name not matching the filename is rejected" 1 sh -c "'$MW' feedback wrong-slug < '$W/mismatch'"
printf -- '---\nname: nowhy\ndescription: A description that is comfortably long enough here\nmetadata:\n  type: feedback\n---\nbody\n' \
  > "$W/nowhy"; ck "feedback without a Why line is rejected" 1 sh -c "'$MW' feedback nowhy < '$W/nowhy'"
ck "a bad slug is rejected" 2 sh -c "echo x | '$MW' feedback 'Not A Slug'"
ck "a bad type is rejected"  2 sh -c "echo x | '$MW' notatype some-slug"
ck "empty stdin is rejected" 2 sh -c "printf '' | '$MW' feedback some-slug"

echo "=== reference memories do not need Why/How ==="
printf -- '---\nname: port-note\ndescription: The service listens on 23306 rather than the default port\nmetadata:\n  type: reference\n---\n\nIt listens on 23306.\n' \
  | "$MW" reference port-note >/dev/null 2>&1
cmp_ "reference accepted without Why" "$?" "0"

echo "=== overwrite protection ==="
good trust-the-file "Read the live file rather than a memory describing it, every time" feedback \
  > "$W/again"
ck "existing file is refused without --update" 1 sh -c "'$MW' feedback trust-the-file < '$W/again'"
ck "--update replaces it"                      0 sh -c "'$MW' feedback trust-the-file --update < '$W/again'"

echo "=== interaction logs are dated, and same-topic-same-day appends ==="
printf '# Session\n\nFirst pass.\n' | "$MW" log my-topic >/dev/null 2>&1
N1=$(ls "$W/memory/interactions"/*my-topic.md 2>/dev/null | wc -l | tr -d ' ')
printf 'Second pass.\n' | "$MW" log my-topic >/dev/null 2>&1
N2=$(ls "$W/memory/interactions"/*my-topic.md 2>/dev/null | wc -l | tr -d ' ')
cmp_ "one log file, not two" "$N2" "$N1"
ckt "the second pass was appended" "grep -q 'Second pass' \"\$(ls '$W/memory/interactions'/*my-topic.md | head -1)\""
ckt "filename is dated"            "ls '$W/memory/interactions' | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-my-topic\.md$'"

echo "=== writing a near-duplicate is reported, not silently accepted ==="
good trust-the-file-again "Read the live file rather than a memory describing it, every single time" feedback \
  > "$W/dup"
ck "duplicate description exits 3" 3 sh -c "'$MW' feedback trust-the-file-again < '$W/dup'"
ckt "but the file was still written, so it can be merged" "[ -f '$W/memory/feedback/trust-the-file-again.md' ]"

echo "=== the duplicate gate has an advisory mode, for corpora that already have debt ==="
# A pre-existing pair must not fail every future write; that is the transition case.
ck "warn mode reports but exits 0" 0 sh -c "RAEMEMBERIT_DUPES=warn '$MW' feedback trust-the-file --update < '$W/again'"
ck "off mode skips the check"      0 sh -c "RAEMEMBERIT_DUPES=off  '$MW' feedback trust-the-file --update < '$W/again'"
ck "default is still blocking"     3 sh -c "'$MW' feedback trust-the-file --update < '$W/again'"
RAEMEMBERIT_DUPES=warn "$MW" feedback trust-the-file --update < "$W/again" > "$W/warnout" 2>&1
if grep -q 'advisory' "$W/warnout"; then printf '  ok    %s\n' "warn mode names the pair as advisory"; pass=$((pass+1))
else printf '  FAIL  %s\n' "warn mode did not label the report advisory"; sed 's/^/          /' "$W/warnout" | tail -4; fail=$((fail+1)); fi

echo "=== the PreCompact message is overridable, and quoting-safe ==="
H="$ROOT/engine/hooks/precompact-notice.sh"
ckt "default is valid JSON"            "bash '$H' | jq -e . >/dev/null"
ckt "override is honoured"             "RAEMEMBERIT_PRECOMPACT_MSG=custom-xyz bash '$H' | grep -q custom-xyz"
# The message is interpolated into JSON; a naive implementation breaks on the first quote someone uses.
ckt "override survives quotes and \$vars" "RAEMEMBERIT_PRECOMPACT_MSG='a \"b\" \$c' bash '$H' | jq -e . >/dev/null"

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
