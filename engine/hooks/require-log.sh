#!/usr/bin/env bash
# Stop — notice when today has no interaction log.
#
# POLICY, via $MEMKIT_REQUIRE_LOG:
#   warn   (default) surface a reminder, allow the session to end
#   strict block the stop (exit 2) until a log exists
#   off    do nothing
#
# The upstream single-user setup used strict. That is a reasonable choice for its author and a
# hostile default for anyone else: a hook that refuses to let someone end their session is the
# fastest route to the whole kit being uninstalled. Strict remains one env var away.
set -uo pipefail
. "$(dirname "$0")/../lib/memkit-root.sh"
MODE="${MEMKIT_REQUIRE_LOG:-warn}"
[ "$MODE" = off ] && exit 0
T=$(date +%Y-%m-%d)
ls "$MEMKIT_MEM/interactions/${T}-"*.md >/dev/null 2>&1 && exit 0
MSG="No interaction log for ${T} in ${MEMKIT_MEM}/interactions/. Consider writing one before the session's context is gone."
if [ "$MODE" = strict ]; then printf '%s\n' "$MSG" >&2; exit 2; fi
jq -n --arg m "$MSG" '{"systemMessage":$m}'
exit 0
