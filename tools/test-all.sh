#!/usr/bin/env bash
# Run every raememberit test. This is what CI runs and what you run before a commit.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rc=0
for t in test-sanitize-scan.sh test-dedup.sh test-mem-write.sh test-install.sh test-docs.sh; do
  printf '\n\033[1;36m▸ %s\033[0m\n' "$t"
  if bash "$ROOT/tools/$t" | tail -1 | sed 's/^/  /'; then :; else rc=1; fi
  # tail -1 hides the detail but not the verdict; a non-zero exit from the pipeline's FIRST stage
  # would be swallowed here, so the scripts are re-run for status rather than trusting the pipe.
  bash "$ROOT/tools/$t" >/dev/null 2>&1 || { printf '  \033[1;31mFAILED\033[0m\n'; rc=1; }
done
printf '\n\033[1;36m▸ sanitize gate\033[0m\n'
bash "$ROOT/tools/sanitize-scan.sh" | tail -2 | sed 's/^/  /'
bash "$ROOT/tools/sanitize-scan.sh" >/dev/null 2>&1 || rc=1
printf '\n'
[ "$rc" -eq 0 ] && printf '\033[1;32mall green\033[0m\n' || printf '\033[1;31msomething failed\033[0m\n'
exit "$rc"
