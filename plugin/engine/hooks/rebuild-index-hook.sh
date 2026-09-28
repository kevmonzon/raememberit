#!/usr/bin/env bash
# SessionEnd — regenerate the indexes from frontmatter so they never drift from the files.
#
# The rebuild's output used to go to /dev/null with `|| true`, which meant a non-zero exit — the
# over-budget verdict included — was discarded with no trace anywhere. It still must not fail the
# session, so the exit code is still swallowed; the OUTPUT now lands in a log, and the verdict in
# $MEM/.index-status, which the SessionStart tripwire surfaces where it can be read.
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
bash "$(dirname "$0")/../rebuild-index.sh" >"$RAEMEMBERIT_MEM/.index-rebuild.log" 2>&1 || true
exit 0
