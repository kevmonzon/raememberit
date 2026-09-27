#!/usr/bin/env bash
# Show what the shipped command templates would say, against the commands you actually have.
#
# WHY THIS EXISTS. The installer deliberately never overwrites a command it did not write, which is
# right — an adopted setup's commands carry that person's own examples and anecdotes, and those are the
# reason the standalone route exists at all. But the cost is silent: kit improvements to command
# MECHANICS never reach them, and nothing ever says so. "Frozen for good reasons" quietly becomes
# "frozen and forgotten".
#
# So: read-only, on demand. It renders each template exactly as the installer would and diffs it against
# what is installed. Nothing is written. Port by hand what is worth porting, ignore the rest — the
# divergence is usually YOUR text, and that is the point.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CFG="$TARGET/raememberit/.config"
PUSER="you"; [ -f "$CFG" ] && PUSER="$(sed -n 's|^user=||p' "$CFG" | tail -1)"; [ -z "$PUSER" ] && PUSER="you"
MEM="${RAEMEMBERIT_MEMORY_DIR:-$TARGET/memory}"

usage() { sed -n '2,20p' "$0"; exit 0; }
STAT=0
case "${1:-}" in -h|--help) usage ;; --stat) STAT=1 ;; esac

printf '\033[1;36m▸ shipped templates vs installed commands\033[0m\n'
printf '  addressee "%s" · corpus %s\n\n' "$PUSER" "$MEM"

any=0
for t in "$SRC/protocol"/*.md.tmpl; do
  [ -e "$t" ] || continue
  b="$(basename "$t" .tmpl)"
  dest="$TARGET/commands/$b"
  if [ ! -e "$dest" ]; then
    printf '  \033[1;33m!\033[0m %-22s not installed\n' "$b"
    continue
  fi
  rendered="${TMPDIR:-/tmp}/rmb-diff.$$"
  sed -e "s/{{USER}}/$PUSER/g" -e "s|{{MEM}}|$MEM|g" \
      -e "s|engine/|$TARGET/raememberit/engine/|g" "$t" > "$rendered"
  if diff -q "$rendered" "$dest" >/dev/null 2>&1; then
    printf '  \033[1;32m=\033[0m %-22s identical to the shipped version\n' "$b"
  else
    any=1
    add=$(diff "$rendered" "$dest" | grep -c '^>' || true)
    del=$(diff "$rendered" "$dest" | grep -c '^<' || true)
    printf '  \033[1;33m≠\033[0m %-22s +%s / -%s lines vs shipped\n' "$b" "$add" "$del"
    if [ "$STAT" = 0 ]; then
      diff -u "$rendered" "$dest" | sed -n '3,$p' | sed 's/^/        /'
      printf '\n'
    fi
  fi
  rm -f "$rendered"
done

if [ "$any" = 0 ]; then
  printf '\n  nothing diverges — your commands are the shipped ones\n'
else
  printf '  \033[2m"+" is text YOU have that the template does not. That is usually the point of adopting\n'
  printf '  this way; port only the mechanics you want. Nothing here writes anything.\033[0m\n'
fi
