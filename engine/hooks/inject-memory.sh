#!/usr/bin/env bash
# UserPromptSubmit — inject the always-on index into context, once per context window.
# The guard file is removed by rearm-inject.sh on PostCompact and on SessionEnd, so a fresh
# context re-injects automatically without a cron or a stale-timestamp heuristic.
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
IDX="$RAEMEMBERIT_MEM/MEMORY.md"
[ -f "$IDX" ] || exit 0
SID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-'); [ -z "$SID" ] && SID=nosid
GUARD="${TMPDIR:-/tmp}/raememberit-injected-$SID"
[ -e "$GUARD" ] && exit 0
: > "$GUARD"
jq -n --rawfile c "$IDX" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$c}}'
