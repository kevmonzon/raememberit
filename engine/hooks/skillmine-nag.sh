#!/usr/bin/env bash
# SessionStart — if enough interaction logs have landed since the last pattern sweep, offer one.
# Never runs the sweep itself; it only offers.
#
# This hook is here because the upstream README documented it while no such hook existed in any
# settings file (found 2026-09-27). Documenting a hook is not having one.
set -uo pipefail
. "$(dirname "$0")/../lib/memkit-root.sh"
THRESH="${MEMKIT_SWEEP_THRESHOLD:-15}"
MARK="$MEMKIT_MEM/.last-sweep"
D="$MEMKIT_MEM/interactions"
[ -d "$D" ] || exit 0
if [ -f "$MARK" ]; then N=$(find "$D" -name '*.md' -newer "$MARK" 2>/dev/null | wc -l | tr -d ' ')
else                    N=$(find "$D" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
fi
[ "$N" -eq 0 ] && exit 0            # nothing logged yet: nothing to sweep
[ "$N" -lt "$THRESH" ] && exit 0
jq -n --arg n "$N" --arg t "$THRESH" \
  '{"systemMessage":("\($n) interaction logs since the last pattern sweep (threshold \($t)). Offer a sweep for recurring patterns worth promoting — do not run one unprompted.")}'
exit 0
