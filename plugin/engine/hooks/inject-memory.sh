#!/usr/bin/env bash
# UserPromptSubmit — inject the always-on index into context, once per context window.
# The guard file is removed by rearm-inject.sh on PostCompact and on SessionEnd, so a fresh
# context re-injects automatically without a cron or a stale-timestamp heuristic.
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IDX="$RAEMEMBERIT_MEM/MEMORY.md"
[ -f "$IDX" ] || exit 0
SID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-'); [ -z "$SID" ] && SID=nosid
GUARD="${TMPDIR:-/tmp}/raememberit-injected-$SID"
[ -e "$GUARD" ] && exit 0
: > "$GUARD"
# A PREAMBLE CARRYING THE CONFIGURATION, so a command file never has to.
#
# The standalone installer renders {{USER}} and {{MEM}} into the command files at install time. A
# plugin cannot do that: its commands are managed files, replaced on every update. The obvious fix —
# have the command read CLAUDE_PLUGIN_OPTION_* itself — is NOT supported by a single example: across
# the 39 official plugins, zero commands read an option; only scripts invoked by hooks do. Options
# reach processes, not prose.
#
# So the hook, which IS a process and does get the options, states them as context instead. Evidenced
# channel, already wired, and it works identically on both routes.
PRE=""
[ -n "${RAEMEMBERIT_USER:-}" ] && PRE="Address the user as ${RAEMEMBERIT_USER} in memory files you write."
PRE="${PRE:+$PRE
}The memory corpus is at ${RAEMEMBERIT_MEM}. Write to it only through ${ENGINE_DIR}/mem-write.sh over Bash — the Edit and Write tools refuse paths inside a .claude directory.

"

jq -n --rawfile c "$IDX" --arg p "$PRE" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":($p + $c)}}'
