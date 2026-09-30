#!/usr/bin/env bash
# Stop — corrections piled up this session and no feedback memory was written since the first one.
#
# The prompt-side detector (correction-nudge.sh) says "this looks like a correction" in the moment.
# This is the other half: at the end of a turn, if this session has logged two or more corrections
# and feedback/ holds nothing newer than the first of them, say so once. Two, not one — one
# correction is a conversation; two is a pattern nobody wrote down.
#
#   RAEMEMBERIT_CORRECTIONS = nudge (default: one systemMessage per session) | strict (block the stop
#                             with exit 2 until a feedback memory lands) | shadow | off
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
MODE="${RAEMEMBERIT_CORRECTIONS:-nudge}"
case "$MODE" in off|shadow) exit 0 ;; esac
LOG="$RAEMEMBERIT_MEM/.corrections-log"
[ -f "$LOG" ] || exit 0
SID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-'); [ -z "$SID" ] && SID=nosid
N=$(awk -F'\t' -v s="$SID" '$3==s' "$LOG" 2>/dev/null | wc -l | tr -d ' '); N=${N:-0}
[ "$N" -ge 2 ] || exit 0
FIRST=$(awk -F'\t' -v s="$SID" '$3==s{print $2; exit}' "$LOG")
# Any feedback memory written after the first correction of this session counts as "learned". The
# log carries epoch seconds for exactly this comparison — `find -newermt` parses timestamps
# differently per platform, and a wrong parse here fails QUIET (nag never fires).
LEARNED=$(python3 - "$RAEMEMBERIT_MEM/feedback" "${FIRST:-0}" <<'PYC'
import glob, os, sys
d, t = sys.argv[1], float(sys.argv[2])
print("yes" if any(os.stat(f).st_mtime > t for f in glob.glob(os.path.join(d, "*.md"))) else "")
PYC
)
[ -z "$LEARNED" ] || exit 0
MSG="raememberit: $N corrections this session and no feedback memory written since the first. If a rule emerged, /learn it before this context is gone."
if [ "$MODE" = strict ]; then printf '%s\n' "$MSG" >&2; exit 2; fi
GUARD="${TMPDIR:-/tmp}/raememberit-learnnag-$SID"
[ -f "$GUARD" ] && exit 0
: > "$GUARD"
jq -n --arg m "$MSG" '{"systemMessage":$m}'
exit 0
