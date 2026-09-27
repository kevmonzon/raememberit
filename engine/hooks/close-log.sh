#!/usr/bin/env bash
# SessionEnd(clear) — stamp today's latest interaction log so a /clear boundary is visible.
set -uo pipefail
. "$(dirname "$0")/../lib/memkit-root.sh"
T=$(date +%Y-%m-%d); N=$(date "+%H:%M")
F=$(ls -t "$MEMKIT_MEM/interactions/${T}-"*.md 2>/dev/null | head -1)
[ -n "$F" ] && printf '\n_Session closed via /clear at %s %s._\n' "$T" "$N" >> "$F"
exit 0
