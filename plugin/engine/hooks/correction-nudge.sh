#!/usr/bin/env bash
# UserPromptSubmit — notice when a prompt reads like a correction, and say so before the model
# answers it.
#
# WHY. /learn is supposed to fire "the moment the user corrects you". That trigger lives in prose, so
# it fires when the model notices — and the moment it most needs to notice is the moment it is busy
# being wrong. This is a process instead: a small set of correction shapes, matched against the
# prompt, that (a) appends the correction to <corpus>/.corrections-log so the pattern is countable
# later, and (b) in `nudge` mode adds one line of context saying this looks like a correction and
# naming /learn. The Stop-side counterpart, learn-nag.sh, notices when corrections piled up and no
# feedback memory was written.
#
# The shapes are deliberately STRONG. "always" and "never" are everywhere; "no, " at the start of a
# prompt, "I told you", "you should have" are not. A detector that fires on ordinary prose is one the
# reader learns to ignore, which costs more than a missed correction — the log still records the miss
# as absence, and /skill-mine reads friction from it.
#
#   RAEMEMBERIT_CORRECTIONS = nudge (default) | shadow (log only) | off
set -uo pipefail
. "$(dirname "$0")/../lib/raememberit-root.sh"
MODE="${RAEMEMBERIT_CORRECTIONS:-nudge}"
[ "$MODE" = off ] && exit 0
IN=$(cat)
PROMPT=$(printf '%s' "$IN" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0
case "$PROMPT" in /*) exit 0 ;; esac
SID=$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-'); [ -z "$SID" ] && SID=nosid

# Leading shapes (start of prompt) and anywhere shapes, case-insensitive. Kept in two lists so each
# can be tuned without loosening the other.
LEAD='^[[:space:]]*(no[,.!:; ]|nope\b|wrong[,.!]|not that\b|not what i\b|stop[,.!]|actually[,]|again\?|why did you\b|you should have\b|that is not\b|that'"'"'s not\b|i (already )?(told|said|asked)\b|please don'"'"'t\b|don'"'"'t (do|use|run|touch|change)\b)'
ANY='\b(i (already )?told you|as i (said|told you)|i (already )?said|next time|you keep\b|you always\b|not again|for the (second|third|nth) time|stop (doing|using|running|changing))\b'
HIT=0
printf '%s\n' "$PROMPT" | head -c 400 | grep -qiE "$LEAD" && HIT=1
[ "$HIT" = 0 ] && printf '%s\n' "$PROMPT" | grep -qiE "$ANY" && HIT=1
[ "$HIT" = 1 ] || exit 0

# Columns: ISO stamp (for people), epoch seconds (for the Stop hook's comparison — portable, no
# timezone parsing), session id, the first 160 characters of the prompt.
SNIP=$(printf '%s' "$PROMPT" | tr '\n\t' '  ' | head -c 160)
printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" "$SID" "$SNIP" >> "$RAEMEMBERIT_MEM/.corrections-log"
[ "$MODE" = shadow ] && exit 0

# One nudge per ten minutes per session: a user mid-argument does not need the same line on every turn.
GUARD="${TMPDIR:-/tmp}/raememberit-nudged-$SID"
if [ -f "$GUARD" ] && [ -n "$(find "$GUARD" -mmin -10 2>/dev/null)" ]; then exit 0; fi
: > "$GUARD"
jq -n '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"raememberit: this prompt reads like a correction. If a durable rule about how to work emerged from it, capture it now with /learn — mid-task, while the sentence that corrected you is still exact."}}'
exit 0
