#!/usr/bin/env bash
# UserPromptSubmit — score this prompt against the memory catalog and the installed skills, and
# surface the best few. See ../context-router.py for the whole rationale; this is the wrapper that
# resolves the corpus and hands stdin through.
#
# Both features default to SHADOW: they log what they would have surfaced to <corpus>/.recall-log and
# <corpus>/.skill-log and inject nothing. Flip to `inject` once a week of log says the hits are worth
# their bytes. `off` skips the process entirely.
#   RAEMEMBERIT_AUTORECALL   shadow | inject | off
#   RAEMEMBERIT_SKILLROUTER  shadow | inject | off
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
[ "${RAEMEMBERIT_AUTORECALL:-shadow}" = off ] && [ "${RAEMEMBERIT_SKILLROUTER:-shadow}" = off ] && exit 0
[ -f "$RAEMEMBERIT_MEM/MEMORY-CATALOG.md" ] || exit 0
exec python3 "$(dirname "$0")/../context-router.py"
