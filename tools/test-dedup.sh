#!/usr/bin/env bash
# Test the duplicate-prevention loop end to end, on a throwaway corpus.
#
#     tools/test-dedup.sh
#
# This exists because the corpus's most common defect is duplicate memories, and the original
# guard against it was a paragraph of prose asking the assistant to "check first". That has a
# measured failure rate: three files, one fact, four hours, one person. Prose cannot be tested.
# These two mechanisms can:
#   engine/find-similar.py                        flags the collision BEFORE the write
#   run_eval.py --health --strict-dupes           refuses the corpus AFTER a bad write
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Knobs an adopted setup may set in settings.json reach a running session's tool environment.
# A suite that inherits them is not testing the shipped defaults.
unset RAEMEMBERIT_DUPES RAEMEMBERIT_REQUIRE_LOG RAEMEMBERIT_MEMORY_DIR RAEMEMBERIT_RECENT_N 2>/dev/null || true
W="${TMPDIR:-/tmp}/raememberit-dedup.$$"
export CLAUDE_CONFIG_DIR="$W"
mkdir -p "$W/memory"/{feedback,project,reference,interactions,eval}
trap 'rm -rf "$W"' EXIT

pass=0; fail=0
ck() { local n="$1" e="$2"; shift 2
  "$@" >"$W/out" 2>&1; local a=$?
  if [ "$a" = "$e" ]; then printf '  ok    %s\n' "$n"; pass=$((pass+1))
  else printf '  FAIL  %s (expected %s, got %s)\n' "$n" "$e" "$a"
       sed 's/^/          /' "$W/out" | head -8; fail=$((fail+1)); fi; }

mk() { # slug, description
  cat > "$W/memory/feedback/$1.md" <<EOF
---
name: $1
description: $2
metadata:
  type: feedback
---

Body for $1.

**Why:** test fixture.
**How to apply:** it is a fixture.
EOF
}

DESC="a build tool's shims fail silently in a fresh worktree until the toolchain is trusted"

echo "=== empty corpus ==="
ck "strict-dupes passes on an empty corpus" 0 \
   python3 "$ROOT/engine/eval/run_eval.py" --health --strict-dupes

echo "=== one memory: no collision to find ==="
mk shim-trust-first "$DESC"
ck "strict-dupes still passes with one memory" 0 \
   python3 "$ROOT/engine/eval/run_eval.py" --health --strict-dupes

echo "=== the pre-write check must SEE the collision ==="
python3 "$ROOT/engine/find-similar.py" --desc "$DESC" worktree toolchain shims > "$W/sim" 2>&1
if grep -q "LIKELY DUPLICATE" "$W/sim"; then
  echo "  ok    find-similar flags the near-identical description"; pass=$((pass+1))
else
  echo "  FAIL  find-similar missed an identical description"; sed 's/^/          /' "$W/sim" | head -8; fail=$((fail+1))
fi

echo "=== writing the duplicate anyway must be REFUSED after the fact ==="
mk trust-toolchain-in-worktree "$DESC and must be trusted first"
ck "strict-dupes rejects the corpus once a duplicate lands" 1 \
   python3 "$ROOT/engine/eval/run_eval.py" --health --strict-dupes

echo "=== and passes again once the duplicate is merged away ==="
rm -f "$W/memory/feedback/trust-toolchain-in-worktree.md"
ck "strict-dupes passes after the duplicate is removed" 0 \
   python3 "$ROOT/engine/eval/run_eval.py" --health --strict-dupes

echo "=== a genuinely different memory must NOT be flagged ==="
python3 "$ROOT/engine/find-similar.py" --desc "pull requests must cite file and line in review comments" \
        pull request review > "$W/sim2" 2>&1
if grep -q "LIKELY DUPLICATE" "$W/sim2"; then
  echo "  FAIL  false positive on an unrelated fact"; fail=$((fail+1))
else
  echo "  ok    unrelated fact is not flagged"; pass=$((pass+1))
fi

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
