#!/usr/bin/env bash
# Self-test for tools/sanitize-scan.sh. Run it before trusting the gate.
#     tools/test-sanitize-scan.sh
#
# PUBLIC-SAFE BY CONSTRUCTION: every probe is either a well-known fake secret shape or an
# invented placeholder term. No real internal vocabulary appears here — the same reason the
# denylist itself is split. Vocabulary probes belong in the private profile repo's own test.
#
# bash 3.2 compatible (macOS /bin/bash).
# PROBE LITERALS ARE SPLIT ("gh""p_") ON PURPOSE: the strings are reassembled at runtime so
# this file contains no token the scanner would match. That keeps the gate free of exclusions
# — an excluded file is a blind spot, and a security gate with blind spots is decoration.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/tools/sanitize-scan.sh"
WORK="${TMPDIR:-/tmp}/memkit-scantest.$$"
mkdir -p "$WORK/repo/tools"
trap 'rm -rf "$WORK"' EXIT

# a miniature repo so probes never touch the real tree
cp "$SCAN" "$WORK/repo/tools/"
cp "$ROOT/tools/denylist.example.txt" "$WORK/repo/tools/"
S="$WORK/repo/tools/sanitize-scan.sh"
printf 'nothing to see here\n' > "$WORK/repo/ok.md"

pass=0; fail=0
check() { # name expected_exit cmd...
  local n="$1" e="$2"; shift 2
  "$@" >"$WORK/out" 2>&1; local a=$?
  if [ "$a" = "$e" ]; then printf '  ok    %s\n' "$n"; pass=$((pass+1))
  else printf '  FAIL  %s (expected exit %s, got %s)\n' "$n" "$e" "$a"
       sed 's/^/          /' "$WORK/out" | head -6; fail=$((fail+1)); fi
}
probe() { printf '%s\n' "$2" > "$WORK/repo/probe.md"; check "$1" 1 "$S"; rm -f "$WORK/repo/probe.md"; }

echo "=== baseline ==="
check "clean tree passes" 0 "$S"
check "zero files scanned is an ERROR, not a pass" 2 "$S" "$WORK/definitely-absent"

echo "=== secret shapes (public knowledge; all values fake) ==="
probe "GitHub token"      "tok: gh""p_0000000000000000000A"
probe "Anthropic key"     "key: sk-""ant-0000000000000000000A"
probe "AWS access key id" "id: AKI""AIOSFODNN7EXAMPLE"
probe "Slack token"       "tok: xox""b-0000000000-0000000000-aaaaaaaaaa"
probe "bearer token"      "Authorization: Bea""rer 000000000000000000000000"
probe "private key block" "-----BEG""IN RSA PRIVATE KEY-----"
probe "ECR account id"    "host: 000000000000.d""kr.ecr.ap-northeast-1.amazonaws.com"

echo "=== identifying paths and unfilled slots ==="
probe "absolute macOS home path" "cd /Use""rs/somebody/thing"
probe "absolute Linux home path" "cd /ho""me/somebody/thing"
probe "unfilled template slot"   "greeting for {{""USER}}"

echo "=== per-line escape hatch ==="
printf 'cd /Use%ss/somebody/thing\n' "r" > "$WORK/repo/probe.md"
check "violation blocks without the marker" 1 "$S"
printf 'cd /Use%ss/somebody/thing   # sanitize-allow: deliberate example path\n' "r" > "$WORK/repo/probe.md"
check "same line passes WITH the marker" 0 "$S"
rm -f "$WORK/repo/probe.md"

echo "=== additivity: a private list must EXTEND the shapes, never replace them ==="
# invented term — proves the mechanism without naming anything real
printf 'FAIL\tZZQQ_PLACEHOLDER_TERM\tinvented probe term\n' > "$WORK/private.txt"
printf 'ZZQQ_PLACEHOLDER_TERM\n' > "$WORK/repo/probe.md"
check "private rule blocks"                1 env MEMKIT_DENYLIST="$WORK/private.txt" "$S"
printf 'tok: %s\n' 'gh''p_0000000000000000000A' > "$WORK/repo/probe.md"
check "shape rule STILL blocks with a private list loaded" \
                                           1 env MEMKIT_DENYLIST="$WORK/private.txt" "$S"
rm -f "$WORK/repo/probe.md"

echo "─────"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
