#!/usr/bin/env bash
# SessionEnd — regenerate the indexes from frontmatter so they never drift from the files.
#
# The rebuild's output used to go to /dev/null with `|| true`, which meant a non-zero exit — the
# over-budget verdict included — was discarded with no trace anywhere. It still must not fail the
# session, so the exit code is still swallowed; the OUTPUT now lands in a log, and the verdict in
# $MEM/.index-status, which the SessionStart tripwire surfaces where it can be read.
#
# DETACHED, NOT AWAITED. On exit the harness gives SessionEnd hooks a short budget of its own —
# the `timeout` in the wiring does not extend it — and a ~1.7s rebuild on a real corpus overran it,
# so every exit printed "Hook cancelled" and the index never refreshed. The rebuild now runs in the
# background and the hook returns at once. Safe to abandon mid-run: rebuild-index.sh stages to
# temps and mv's them in, so a killed rebuild leaves the previous index intact.
#   set -m      — own process group, so a signal sent to the hook's group does not reach it
#   nohup       — survives the terminal closing
#   </dev/null >log 2>&1 — every inherited fd released, or the harness waits on the pipe anyway
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
set -m
nohup bash "$(dirname "$0")/../rebuild-index.sh" \
  </dev/null >"$RAEMEMBERIT_MEM/.index-rebuild.log" 2>&1 &
exit 0
