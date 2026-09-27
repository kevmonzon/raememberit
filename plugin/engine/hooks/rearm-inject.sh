#!/usr/bin/env bash
# PostCompact / SessionEnd — drop the injection guard so the next context re-injects.
set -uo pipefail
SID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')
[ -n "$SID" ] && rm -f "${TMPDIR:-/tmp}/raememberit-injected-$SID"
exit 0
