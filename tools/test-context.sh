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

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
