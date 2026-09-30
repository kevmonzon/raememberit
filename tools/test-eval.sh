#!/usr/bin/env bash
# The eval harness's own honesty: what it says when an expectation, not retrieval, is at fault.
#
#     tools/test-eval.sh
#
# WHY THIS SUITE EXISTS. An `expect` entry naming a file that had been renamed scored as
# `MISS (0/1 retrieved)` — the identical line retrieval prints when it genuinely fails — for
# eight days, while the memory sat at rank 1 under both strategies. And a `path_claim` for a tool
# not installed on the machine read as GONE, which is the word for rot. Both are the harness
# answering a different question from the one it was asked. Each assertion below is one of those
# wrong answers, pinned so it cannot come back.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
unset RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_QUERIES 2>/dev/null || true
W="${TMPDIR:-/tmp}/raememberit-eval.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; fail=$((fail+1)); }

EVAL="$ROOT/engine/eval/run_eval.py"
CFG="$W/cfg"; MEM="$CFG/memory"
mkdir -p "$MEM/feedback" "$MEM/project" "$MEM/reference" "$MEM/interactions" "$MEM/eval" "$CFG/projects"

# ---- fixtures: one memory that was renamed, one path claim, one control ---------------------
mem() { # $1 dir, $2 stem, $3 description
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: %s\n---\n\nbody about %s\n' \
    "$2" "$3" "$1" "$3" > "$MEM/$1/$2.md"
}
mem project   ticket-9001-widget-gateway "TICKET-9001 widget gateway shipped as draft PR"
mem reference tool-x-config             "tool-x reads its config from the yaml under home"
mem feedback  unrelated-control         "an unrelated rule about naming branches"

# ---- queries: the renamed expectation, the tool-less path claim, the same claim with a tool ---
cat > "$MEM/eval/queries.json" <<'JSON'
{"version": 1, "queries": [
  {"id": "renamed",   "category": "ticket-exact", "query": "TICKET-9001", "variants": ["TICKET-9001", "widget gateway"],
   "expect": ["project/2026-01-01-ticket-9001-widget-gateway.md"], "mode": "any"},
  {"id": "by-name",   "category": "ticket-exact", "query": "TICKET-9001", "variants": ["TICKET-9001"],
   "expect": ["ticket-9001-widget-gateway"], "mode": "any"},
  {"id": "gone-tool", "category": "freshness", "query": "tool-x config", "variants": ["tool-x", "config"],
   "expect": ["reference/tool-x-config.md"], "mode": "any",
   "path_claim": "~/.config/raememberit-test-eval-no-such-tool/x.yaml", "requires_tool": "raememberit-no-such-tool-zz"},
  {"id": "have-tool", "category": "freshness", "query": "tool-x config", "variants": ["tool-x", "config"],
   "expect": ["reference/tool-x-config.md"], "mode": "any",
   "path_claim": "~/.config/raememberit-test-eval-no-such-tool/x.yaml", "requires_tool": "python3"},
  {"id": "all-mode-missing", "category": "multi-hop", "query": "TICKET-9001", "variants": ["TICKET-9001"],
   "expect": ["project/ticket-9001-widget-gateway.md", "project/never-existed.md"], "mode": "all"},
  {"id": "control",   "category": "negative-control", "query": "zzz-no-such-term", "variants": ["zzz-no-such-term"],
   "expect": [], "mode": "none"}
]}
JSON

J="$W/out.json"
CLAUDE_CONFIG_DIR="$CFG" python3 "$EVAL" --json > "$J" 2> "$W/err" || true
[ -s "$J" ] && ok "harness ran to JSON on the fixture corpus" || bad "harness produced no JSON" "$(cat "$W/err")"

det() { python3 -c "
import json,sys; d=json.load(open('$J'))
for r in d['runs']['$1']['results']:
    if r['id']=='$2': print(r.get('detail',''))" ; }
passed() { python3 -c "
import json; d=json.load(open('$J'))
print([r['passed'] for r in d['runs']['$1']['results'] if r['id']=='$2'][0])" ; }

echo "=== a renamed expectation is reported as missing, with the rename named ==="
d=$(det literal renamed)
case "$d" in *"EXPECT-MISSING: project/2026-01-01-ticket-9001-widget-gateway.md"*) ok "literal: names the missing expectation";; *) bad "literal: missing expectation not named" "$d";; esac
case "$d" in *"renamed? now project/ticket-9001-widget-gateway.md"*) ok "literal: hints the current file";; *) bad "literal: no rename hint" "$d";; esac
case "$d" in *"MISS (0/"*) bad "literal: still disguised as a retrieval MISS" "$d";; *) ok "literal: not disguised as a retrieval MISS";; esac
[ "$(passed literal renamed)" = "False" ] && ok "a missing expectation never turns the test green" || bad "missing expectation counted as a pass"

echo "=== a bare name: resolves through frontmatter ==="
d=$(det literal by-name)
case "$d" in "best rank 1"*) ok "bare-name expectation resolves and ranks 1";; *) bad "bare-name expectation did not resolve" "$d";; esac

echo "=== a path claim for a tool that is not installed is UNVERIFIABLE, not GONE ==="
d=$(det expanded gone-tool)
case "$d" in *"UNVERIFIABLE (raememberit-no-such-tool-zz not installed)"*) ok "absent tool: reported unverifiable";; *) bad "absent tool: not reported unverifiable" "$d";; esac
case "$d" in *GONE*) bad "absent tool: still says GONE" "$d";; *) ok "absent tool: does not say GONE";; esac
d=$(det expanded have-tool)
case "$d" in *"claimed path GONE"*) ok "present tool, absent path: still GONE (rot is still reported)";; *) bad "present tool, absent path: GONE lost" "$d";; esac

echo "=== mode all: the missing member is on the line, not dropped from the denominator ==="
d=$(det expanded all-mode-missing)
case "$d" in *"EXPECT-MISSING: project/never-existed.md"*) ok "all-mode: missing member named";; *) bad "all-mode: missing member silently dropped" "$d";; esac
[ "$(passed expanded all-mode-missing)" = "False" ] && ok "all-mode: not green with a missing member" || bad "all-mode: green with a missing member"

echo "=== control ==="
[ "$(passed literal control)" = "True" ] && ok "negative control still clean" || bad "negative control broke" "$(det literal control)"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
