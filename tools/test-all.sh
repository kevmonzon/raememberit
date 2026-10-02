#!/usr/bin/env bash
# Run every raememberit test. This is what CI runs and what you run before a commit.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rc=0
for t in test-sanitize-scan.sh test-dedup.sh test-mem-write.sh test-install.sh test-plugin.sh test-tripwire.sh test-eval.sh test-context.sh test-wizard.sh test-docs.sh; do
  printf '\n\033[1;36m▸ %s\033[0m\n' "$t"
  # One run, captured to files: no pipe to swallow the exit status, and the output is still here
  # when it is needed. The three-run version showed only the last line, so the first CI run ever
  # said "FAILED" three times and named nothing — the cause took a local reproduction to find.
  out="$(mktemp)"; err="$(mktemp)"
  bash "$ROOT/tools/$t" >"$out" 2>"$err"; st=$?
  tail -1 "$out" | sed 's/^/  /'
  bad=0
  [ "$st" -eq 0 ] || { printf '  \033[1;31mFAILED\033[0m\n'; bad=1; }
  # A suite can report "N passed, 0 failed" while assertions never ran — an undefined helper prints
  # to stderr and the tally never sees it. Treat that as a failure, because a green run that skipped
  # checks is the same defect as a pipeline that fakes a pass.
  if grep -qE 'command not found|No such file or directory' "$out" "$err"; then
    printf '  \033[1;31mFAILED — a suite emitted shell errors; assertions may not have run\033[0m\n'; bad=1
  fi
  if [ "$bad" -eq 1 ]; then
    rc=1
    printf '  ── full output of %s ──\n' "$t"; sed 's/^/    /' "$out"
    [ -s "$err" ] && { printf '  ── stderr ──\n'; sed 's/^/    /' "$err"; }
  fi
  rm -f "$out" "$err"
done
printf '\n\033[1;36m▸ sanitize gate\033[0m\n'
bash "$ROOT/tools/sanitize-scan.sh" | tail -2 | sed 's/^/  /'
bash "$ROOT/tools/sanitize-scan.sh" >/dev/null 2>&1 || rc=1
printf '\n'
[ "$rc" -eq 0 ] && printf '\033[1;32mall green\033[0m\n' || printf '\033[1;31msomething failed\033[0m\n'
exit "$rc"
