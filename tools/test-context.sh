#!/usr/bin/env bash
# The context layer: domain tags, the native silo listing, and the prompt-time hooks that make
# retrieval and skill use involuntary rather than instruction-driven.
#
#     tools/test-context.sh
#
# WHY THIS SUITE EXISTS. Capture in this kit is enforced by a script; retrieval was a paragraph in a
# CLAUDE.md asking the assistant to run /recall first. A paragraph has the failure rate every other
# paragraph here had. The hooks below move retrieval and skill routing into processes, and this
# asserts them — including that their SHADOW modes write a log and inject nothing, because a hook
# that injects before its precision is measured is the always-on tier growing by another door.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
unset RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_RECENT_N \
      RAEMEMBERIT_AUTORECALL RAEMEMBERIT_SKILLROUTER RAEMEMBERIT_CORRECTIONS RAEMEMBERIT_USER 2>/dev/null || true
W="${TMPDIR:-/tmp}/raememberit-context.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; fail=$((fail+1)); }

MW="$ROOT/engine/mem-write.sh"; REBUILD="$ROOT/engine/rebuild-index.sh"
CFG="$W/cfg"; MEM="$CFG/memory"
mkdir -p "$MEM"/{feedback,project,reference,interactions,eval,archive}
export CLAUDE_CONFIG_DIR="$CFG"

mem() {  # type slug desc [extra-frontmatter-lines...]
  local t="$1" s="$2" d="$3"; shift 3
  { printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: %s\n' "$s" "$d" "$t"
    for l in "$@"; do printf '  %s\n' "$l"; done
    printf -- '---\n\nbody\n\n**Why:** fixture.\n**How to apply:** fixture.\n'; } | RAEMEMBERIT_DUPES=off "$MW" "$t" "$s" >/dev/null 2>&1
}

echo "=== metadata.domain: enforced on write, indexed on rebuild ==="
mem reference payments-sysparams "The payments service keeps its system parameters in a table the admin screen edits" "domain: payments"
[ -f "$MEM/reference/payments-sysparams.md" ] && ok "a memory with a valid domain is written" || bad "valid domain refused"
mem project billing-node-upgrade "Upgrading the billing frontend toolchain to a newer runtime, draft PR open" "domain: billing-api, node"
grep -q 'domain: billing-api, node' "$MEM/project/billing-node-upgrade.md" && ok "a comma-separated domain list is accepted" || bad "domain list refused"
mem reference untagged-fact "A reference memory that declares no domain at all and must still index normally"
out=$(printf -- '---\nname: bad-dom\ndescription: A description long enough to pass the length gate here\nmetadata:\n  type: reference\n  domain: Not A Domain\n---\nbody\n' | RAEMEMBERIT_DUPES=off "$MW" reference bad-dom 2>&1); rc=$?
[ "$rc" = 1 ] && ok "a malformed domain is refused (exit $rc)" || bad "a malformed domain was accepted (exit $rc)"
printf '%s' "$out" | grep -q 'kebab-case' && ok "and the refusal says what shape it wants" || bad "refusal does not explain the shape"
[ ! -f "$MEM/reference/bad-dom.md" ] && ok "nothing was written" || bad "the refused memory landed anyway"

RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$REBUILD" >/dev/null 2>&1
[ -f "$MEM/.domain-index" ] && ok "rebuild writes .domain-index" || bad "no .domain-index after rebuild"
n=$(grep -c . "$MEM/.domain-index" 2>/dev/null || echo 0)
[ "$n" = 3 ] && ok "one row per (domain, memory): 3" || bad "expected 3 domain rows, got $n"
grep -q "^payments	reference/payments-sysparams.md	payments-sysparams	The payments service" "$MEM/.domain-index" \
  && ok "rows are domain, corpus-relative path, name, description" || bad "row shape is wrong" "$(head -3 "$MEM/.domain-index")"
grep -q "^node	" "$MEM/.domain-index" && grep -q "^billing-api	" "$MEM/.domain-index" && ok "each token of a list becomes its own row" || bad "list tokens not split"
grep -q 'payments-sysparams.*· domain: payments' "$MEM/MEMORY-CATALOG.md" && ok "the catalog line shows the domain, so /recall greps catch it" || bad "catalog line has no domain"
grep -q 'untagged-fact' "$MEM/MEMORY-CATALOG.md" && ! grep -q 'untagged-fact.*domain:' "$MEM/MEMORY-CATALOG.md" \
  && ok "an untagged memory indexes without a suffix" || bad "untagged memory line is wrong"
mem feedback payments-craft-rule "When touching payments handlers always run the generated-code check first" "scope: domain" "domain: payments"
mem feedback global-rule "A standing rule that changes behaviour on every task whatever the repo" "scope: global" "domain: payments"
RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$REBUILD" >/dev/null 2>&1
grep -q 'global-rule' "$MEM/MEMORY.md" && ! grep -q 'global-rule.*domain:' "$MEM/MEMORY.md" \
  && ok "the always-on tier never carries the domain suffix (its bytes are budgeted)" || bad "domain suffix leaked into the always-on tier"
grep -q "^payments	.*payments-craft-rule" "$MEM/.domain-index" && ok "domain-scoped feedback is in the domain index" || bad "domain feedback missing from the domain index"

echo "=== the native auto-memory silo is listed in the catalog, read-only ==="
! grep -q 'Native auto-memory' "$MEM/MEMORY-CATALOG.md" && ok "no section when no native store exists" || bad "native section present with no stores"
mkdir -p "$CFG/projects/-Users-x-code-app/memory" "$CFG/projects/-Users-x-other/memory"
printf -- '---\nname: colima-cert\ndescription: colima needs the corporate CA imported before docker pull works\n---\nbody\n' > "$CFG/projects/-Users-x-code-app/memory/colima-cert.md"
printf '# Memory Index\n- [x](x.md) — an index file with no frontmatter, described by its heading\n' > "$CFG/projects/-Users-x-other/memory/MEMORY.md"
RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$REBUILD" >/dev/null 2>&1
grep -q '## Native auto-memory' "$MEM/MEMORY-CATALOG.md" && ok "section appears once stores exist" || bad "native section missing"
grep -q -- '- \[-Users-x-code-app/colima-cert\](.*colima-cert.md) — colima needs the corporate CA' "$MEM/MEMORY-CATALOG.md" \
  && ok "entries are store/stem with the description" || bad "native entry shape is wrong" "$(grep -A3 'Native auto' "$MEM/MEMORY-CATALOG.md")"
grep -q -- '- \[-Users-x-other/MEMORY\](.*) — Memory Index' "$MEM/MEMORY-CATALOG.md" \
  && ok "a store's index file falls back to its heading" || bad "heading fallback failed"
! grep -q 'colima-cert' "$MEM/MEMORY.md" && ok "native memories stay out of the always-on tier" || bad "native memory leaked into MEMORY.md"
[ "$(find "$CFG/projects" -name '*.md' | wc -l | tr -d ' ')" = 2 ] && ok "the silo was read, not written" || bad "the silo changed"

echo "=== the context router: prompt → memories and skills, shadow by default ==="
ROUTER="$ROOT/engine/hooks/context-router.sh"
# Fixtures: a corpus (built above), two commands and one skill in the config dir.
mkdir -p "$CFG/commands" "$CFG/skills/release-notes"
printf -- '---\nname: deploy-checklist\ndescription: Use when deploying the billing service to staging — the runbook steps that are easy to skip\n---\nbody\n' > "$CFG/commands/deploy-checklist.md"
printf -- '---\nname: unrelated-thing\ndescription: Use when carving pumpkins for a seasonal office decoration contest\n---\nbody\n' > "$CFG/commands/unrelated-thing.md"
printf -- '---\nname: release-notes\ndescription: Use when writing release notes for the billing service from merged pull requests\n---\nbody\n' > "$CFG/skills/release-notes/SKILL.md"
mem reference pay-123-outage "PAY-123 was the outage where the payments queue stalled after a deploy to staging"
RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$REBUILD" >/dev/null 2>&1
rm -f "$MEM/.recall-log" "$MEM/.skill-log"
route() {  # sid prompt cwd [env...]  -> stdout
  local sid="$1" prompt="$2" cwd="$3"; shift 3
  printf '{"session_id":"%s","prompt":%s,"cwd":"%s"}' "$sid" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$prompt")" "$cwd" \
    | env RAEMEMBERIT_MEMORY_DIR="$MEM" CLAUDE_CONFIG_DIR="$CFG" "$@" bash "$ROUTER" 2>/dev/null
}
rm -f "${TMPDIR:-/tmp}"/raememberit-surfaced-ctx*
out=$(route ctx1 "the billing node upgrade is failing when deploying to staging, help me" "/x/somewhere")
[ -z "$out" ] && ok "shadow mode injects nothing" || bad "shadow mode produced output" "$out"
grep -q 'auto-shadow' "$MEM/.recall-log" 2>/dev/null && ok "shadow mode logs the memories it would have surfaced" || bad "no recall log line in shadow mode"
grep -q 'project/billing-node-upgrade.md' "$MEM/.recall-log" && ok "the matching memory is the one logged" || bad "wrong memory logged" "$(cat "$MEM/.recall-log")"
! grep -q 'untagged-fact' "$MEM/.recall-log" && ok "an unrelated memory is not surfaced" || bad "an unrelated memory was surfaced"
grep -q 'deploy-checklist' "$MEM/.skill-log" 2>/dev/null && ok "the matching command is logged as a skill candidate" || bad "no skill log line" "$(cat "$MEM/.skill-log" 2>/dev/null)"
! grep -q 'unrelated-thing' "$MEM/.skill-log" && ok "an unrelated command is not a candidate" || bad "unrelated command surfaced"
[ -f "$MEM/.skill-index" ] && grep -q 'release-notes	skill	' "$MEM/.skill-index" && ok "the skill index covers skills dirs as well as commands" || bad "skill index missing or incomplete"

out=$(route ctx2 "the billing node upgrade is failing when deploying to staging, help me" "/x/somewhere" RAEMEMBERIT_AUTORECALL=inject RAEMEMBERIT_SKILLROUTER=inject)
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "additionalContext" in d["hookSpecificOutput"]' 2>/dev/null \
  && ok "inject mode emits valid hook JSON" || bad "inject mode output is not valid hook JSON" "$out"
printf '%s' "$out" | grep -q 'billing-node-upgrade' && ok "the injected block names the memory" || bad "memory missing from injected block"
printf '%s' "$out" | grep -q 'project/billing-node-upgrade.md' && ok "and its path, so the file can be read" || bad "path missing"
printf '%s' "$out" | grep -q '/deploy-checklist' && ok "the injected block names the skill" || bad "skill missing from injected block"
printf '%s' "$out" | grep -q 'auto-inject' && bad "log mode leaked into output" || ok "and the log records inject mode: $(grep -c 'auto-inject' "$MEM/.recall-log") line(s)"
out2=$(route ctx2 "the billing node upgrade is failing when deploying to staging, help me" "/x/somewhere" RAEMEMBERIT_AUTORECALL=inject RAEMEMBERIT_SKILLROUTER=inject)
[ -z "$out2" ] && ok "the same hits are not surfaced twice in one session" || bad "repeated the same hits in one session" "$out2"

out=$(route ctx3 "please look at what happened with PAY-123 last week" "/x/somewhere" RAEMEMBERIT_AUTORECALL=inject)
printf '%s' "$out" | grep -q 'pay-123-outage' && ok "a ticket key alone routes to the memory that names it" || bad "ticket key did not route" "$out"
out=$(route ctx4 "why does this handler keep timing out under load in production" "/x/code/payments" RAEMEMBERIT_AUTORECALL=inject)
printf '%s' "$out" | grep -q 'payments-sysparams' && ok "the working directory's name routes through the domain index" || bad "cwd domain did not route" "$out"
out=$(route ctx5 "/recall billing node" "/x/code/payments" RAEMEMBERIT_AUTORECALL=inject RAEMEMBERIT_SKILLROUTER=inject)
[ -z "$out" ] && ok "a slash command is left alone" || bad "routed a slash command" "$out"
n_before=$(wc -l < "$MEM/.recall-log" | tr -d ' ')
out=$(route ctx6 "the billing node upgrade is failing when deploying to staging, help me" "/x/somewhere" RAEMEMBERIT_AUTORECALL=off RAEMEMBERIT_SKILLROUTER=off)
[ -z "$out" ] && [ "$(wc -l < "$MEM/.recall-log" | tr -d ' ')" = "$n_before" ] && ok "off mode neither injects nor logs" || bad "off mode did something"
out=$(route ctx7 "the billing node upgrade is failing when deploying to staging, help me" "/x/somewhere" RAEMEMBERIT_AUTORECALL=inject RAEMEMBERIT_AUTORECALL_BUDGET=60)
printf '%s' "$out" | grep -q 'billing-node-upgrade' && bad "a 60-byte budget still admitted a 100-byte line" || ok "the byte budget is respected"
out=$(printf 'not json at all' | env RAEMEMBERIT_MEMORY_DIR="$MEM" CLAUDE_CONFIG_DIR="$CFG" bash "$ROUTER" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "malformed stdin exits 0 silently — a hook must never break a prompt" || bad "malformed stdin: rc=$rc out=$out"
# The skill index is rebuilt when a command appears after it was built.
sleep 1; printf -- '---\nname: pumpkin-carving\ndescription: Use when the billing service deploy to staging needs a pumpkin for luck\n---\nbody\n' > "$CFG/commands/pumpkin-carving.md"
route ctx8 "deploying the billing service to staging again" "/x" >/dev/null
grep -q 'pumpkin-carving' "$MEM/.skill-index" && ok "a new command is picked up by the next prompt" || bad "skill index went stale"
rm -f "${TMPDIR:-/tmp}"/raememberit-surfaced-ctx*

echo "=== the correction detector: a process, not a paragraph ==="
NUDGE="$ROOT/engine/hooks/correction-nudge.sh"; NAG="$ROOT/engine/hooks/learn-nag.sh"
rm -f "$MEM/.corrections-log" "${TMPDIR:-/tmp}"/raememberit-nudged-cor* "${TMPDIR:-/tmp}"/raememberit-learnnag-cor*
nudge() {  # sid prompt [env...]
  local sid="$1" prompt="$2"; shift 2
  printf '{"session_id":"%s","prompt":%s}' "$sid" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$prompt")" \
    | env RAEMEMBERIT_MEMORY_DIR="$MEM" "$@" bash "$NUDGE" 2>/dev/null
}
out=$(nudge cor1 "No, I told you to use the helper, not the Write tool")
printf '%s' "$out" | grep -q 'reads like a correction' && ok "a leading 'No,' plus 'I told you' is nudged" || bad "correction not nudged" "$out"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && ok "the nudge is valid hook JSON" || bad "nudge is not valid JSON"
grep -q "	cor1	No, I told you" "$MEM/.corrections-log" && ok "the correction is logged with its session and snippet" || bad "correction not logged" "$(cat "$MEM/.corrections-log" 2>/dev/null)"
awk -F'\t' 'NF!=4{exit 1}' "$MEM/.corrections-log" && ok "log rows are ISO, epoch, session, snippet" || bad "log row shape is wrong"
out=$(nudge cor1 "Actually, the staging deploy needs the VPN")
[ -z "$out" ] && ok "a second correction within ten minutes is logged but not nudged again" || bad "nudged twice inside the window" "$out"
[ "$(awk -F'\t' '$3=="cor1"' "$MEM/.corrections-log" | wc -l | tr -d ' ')" = 2 ] && ok "both corrections are in the log" || bad "second correction not logged"
out=$(nudge cor2 "Please add a test for the new endpoint and run the linter")
[ -z "$out" ] && ! grep -q "	cor2	" "$MEM/.corrections-log" && ok "an ordinary request is neither nudged nor logged" || bad "false positive on an ordinary request" "$out"
out=$(nudge cor3 "It is always fine to never worry about this")
[ -z "$out" ] && ok "'always' and 'never' in ordinary prose do not fire" || bad "fired on always/never" "$out"
out=$(nudge cor4 "/learn something")
[ -z "$out" ] && ok "a slash command is left alone" || bad "fired on a slash command"
out=$(nudge cor5 "Wrong, that is not the file I meant" RAEMEMBERIT_CORRECTIONS=shadow)
[ -z "$out" ] && grep -q "	cor5	" "$MEM/.corrections-log" && ok "shadow mode logs and says nothing" || bad "shadow mode misbehaved" "$out"
out=$(nudge cor6 "Wrong, that is not the file I meant" RAEMEMBERIT_CORRECTIONS=off)
[ -z "$out" ] && ! grep -q "	cor6	" "$MEM/.corrections-log" && ok "off mode neither nudges nor logs" || bad "off mode did something"

echo "=== the learn nag: corrections piled up and nothing was learned ==="
nag() { printf '{"session_id":"%s"}' "$1" | env RAEMEMBERIT_MEMORY_DIR="$MEM" "${@:2}" bash "$NAG" 2>/dev/null; }
out=$(nag cor2)
[ -z "$out" ] && ok "silent for a session with no corrections" || bad "nagged with no corrections"
out=$(nag cor5)
[ -z "$out" ] && ok "silent after a single correction — one is a conversation" || bad "nagged after one correction"
out=$(nag cor1)
printf '%s' "$out" | grep -q '2 corrections this session and no feedback memory' && ok "two corrections and no feedback write: one systemMessage" || bad "no nag after two corrections" "$out"
out=$(nag cor1)
[ -z "$out" ] && ok "the nag fires once per session" || bad "nagged twice"
# A feedback memory written AFTER the first correction silences it, for a fresh session with the same shape.
nudge cor7 "No, use the other one" >/dev/null; nudge cor7 "Again? I said the other one" >/dev/null
sleep 1; mem feedback learned-it "The rule that came out of being corrected twice in one session, written down" "scope: domain"
out=$(nag cor7)
[ -z "$out" ] && ok "a feedback memory written after the first correction counts as learned" || bad "nagged despite a feedback write" "$out"
# Strict blocks the stop.
nudge cor8 "No, not that" >/dev/null; nudge cor8 "I told you already" >/dev/null
# make the feedback dir look older than the corrections: the fixture written above is newer, so backdate it
touch -t 202001010000 "$MEM"/feedback/*.md
out=$(nag cor8 RAEMEMBERIT_CORRECTIONS=strict 2>&1); rc=$?
[ "$rc" = 2 ] && ok "strict mode blocks the stop (exit 2)" || bad "strict mode did not block (rc=$rc)"
out=$(nag cor8 RAEMEMBERIT_CORRECTIONS=off); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "off mode is silent at Stop too" || bad "off mode nagged"
rm -f "${TMPDIR:-/tmp}"/raememberit-nudged-cor* "${TMPDIR:-/tmp}"/raememberit-learnnag-cor*

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
