#!/usr/bin/env bash
# sanitize-scan.sh — refuse to let identifying or secret-shaped content reach a public repo.
#
#   tools/sanitize-scan.sh [--patterns FILE] [--staged] [PATH ...]
#
# Exit 0 = clean · 1 = FAIL hits · 2 = usage/environment error (including "nothing scanned",
# which is treated as an error, not a pass — a gate that silently scans zero files is worse
# than no gate).
#
# PORTABILITY: written for bash 3.2, which is what macOS still ships (/bin/bash 3.2.57).
# No mapfile, no associative arrays, no ${x^^}. Verified against 3.2 before first use.
#
# WHY THE PATTERNS ARE NOT IN THIS FILE: a denylist of an employer's internal vocabulary,
# committed to a public repo, is itself the disclosure it was written to prevent. So this
# script is a generic engine. It ships only `tools/denylist.example.txt` — universal secret
# SHAPES, which are public knowledge — and reads private vocabulary from a local file that
# is never committed.
#
# Pattern resolution — ADDITIVE, deliberately:
#   base:  tools/denylist.example.txt          (universal secret shapes; always loaded)
#   plus:  $MEMKIT_DENYLIST or .denylist.local.txt   (private vocabulary, if present)
#   or:    --patterns FILE                     (escape hatch: use ONLY that file)
# The private list EXTENDS the shapes; it must never replace them, or enabling the stronger
# internal gate would silently drop every secret-shape rule. A self-test asserts this.
#
# Pattern file format, tab-separated, one rule per line:
#   FAIL<TAB>regex<TAB>why      -> blocks
#   WARN<TAB>regex<TAB>why      -> reports only
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATTERNS=""; STAGED=0; WEAK=0; TARGETS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --patterns) PATTERNS="${2:-}"; shift 2 ;;
    --staged)   STAGED=1; shift ;;
    -h|--help)  sed -n '2,26p' "$0"; exit 0 ;;
    -*)         echo "sanitize-scan: unknown option: $1" >&2; exit 2 ;;
    *)          TARGETS="$TARGETS$1
"; shift ;;
  esac
done

TMP="${TMPDIR:-/tmp}/sanitize-scan.$$"
LIST="$TMP.list"; KEEP="$TMP.keep"; RULES="$TMP.rules"
trap 'rm -f "$TMP".*' EXIT

EXAMPLE="$ROOT/tools/denylist.example.txt"
PRIVATE=""
if [ -n "${MEMKIT_DENYLIST:-}" ] && [ -f "${MEMKIT_DENYLIST}" ]; then PRIVATE="$MEMKIT_DENYLIST"
elif [ -f "$ROOT/.denylist.local.txt" ];                        then PRIVATE="$ROOT/.denylist.local.txt"
fi

: > "$RULES"
if [ -n "$PATTERNS" ]; then                       # explicit override: that file alone
  [ -f "$PATTERNS" ] || { echo "sanitize-scan: pattern file not found: $PATTERNS" >&2; exit 2; }
  cat "$PATTERNS" >> "$RULES"; SRC="$(basename "$PATTERNS")"
else
  [ -f "$EXAMPLE" ] && cat "$EXAMPLE" >> "$RULES"
  if [ -n "$PRIVATE" ]; then cat "$PRIVATE" >> "$RULES"; SRC="shapes + $(basename "$PRIVATE")"
  else                       SRC="$(basename "$EXAMPLE")"; WEAK=1
  fi
fi
grep -cE '^(FAIL|WARN)	' "$RULES" >/dev/null 2>&1 || {
  echo "sanitize-scan: no usable rules loaded — refusing to report a pass." >&2; exit 2; }

# ---- candidate files (bash 3.2: newline-delimited temp files, not arrays) -------------
if [ "$STAGED" = 1 ]; then
  git -C "$ROOT" diff --cached --name-only --diff-filter=ACMR \
    | sed "s|^|$ROOT/|" > "$LIST"
elif [ -n "$TARGETS" ]; then
  printf '%s' "$TARGETS" | while IFS= read -r t; do
    [ -n "$t" ] && find "$t" -type f 2>/dev/null
  done > "$LIST"
else
  find "$ROOT" -type f -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null > "$LIST"
fi

# drop the pattern files (they contain the terms by definition) and binaries
: > "$KEEP"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    "$PATTERNS"|*/denylist.example.txt|*/.denylist.local.txt) continue ;;
  esac
  if LC_ALL=C grep -qI . "$f" 2>/dev/null; then printf '%s\n' "$f" >> "$KEEP"; fi
done < "$LIST"

N=$(wc -l < "$KEEP" | tr -d ' ')
if [ "$N" -eq 0 ]; then
  if [ "$STAGED" = 1 ]; then echo "sanitize-scan: no staged text files — nothing to check"; exit 0; fi
  echo "sanitize-scan: scanned ZERO files — refusing to report a pass. Check the path/env." >&2
  exit 2
fi

# ---- scan ---------------------------------------------------------------------------
fails=0; warns=0
while IFS='	' read -r sev rx why; do
  case "${sev:-}" in FAIL|WARN) ;; *) continue ;; esac
  [ -n "${rx:-}" ] || continue
  hits=$(tr '\n' '\0' < "$KEEP" | xargs -0 grep -InE -- "$rx" 2>/dev/null || true)
  # Per-LINE escape hatch: a line carrying the marker below is exempt. Used for content that
  # must legitimately name a person — a LICENSE copyright holder, an AUTHORS entry. Deliberately
  # per-line rather than per-file: a file exclusion is an invisible blind spot, whereas every
  # marker is one grep away and shows up in review as an added line.
  hits=$(printf '%s\n' "$hits" | grep -v 'sanitize-allow' || true)
  [ -z "$hits" ] && continue
  if [ "$sev" = FAIL ]; then
    fails=$((fails+1)); printf '\033[1;31mFAIL\033[0m  %s\n' "${why:-$rx}"
  else
    warns=$((warns+1)); printf '\033[1;33mWARN\033[0m  %s\n' "${why:-$rx}"
  fi
  printf '%s\n' "$hits" | sed "s|^$ROOT/||" | head -12 | sed 's/^/        /'
done < "$RULES"

echo "─────"
printf 'scanned %s files · %s rules · %s\n' "$N" "$(grep -cE '^(FAIL|WARN)	' "$RULES")" "$SRC"
[ "$WEAK" = 1 ] && printf '\033[1;33mnote\033[0m  using denylist.example.txt (secret shapes only). Create .denylist.local.txt for the full gate.\n'
if [ "$fails" -gt 0 ]; then
  printf '\033[1;31m%s FAIL rule(s) matched — refusing.\033[0m\n' "$fails"; exit 1
fi
printf '\033[1;32mclean\033[0m'
[ "$warns" -gt 0 ] && printf ' (%s warning rule(s) — review, not blocking)' "$warns"
echo
exit 0
