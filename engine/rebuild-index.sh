#!/usr/bin/env bash
# Regenerate the two indexes from each memory's frontmatter.
#
#   MEMORY.md          ALWAYS-ON  — injected into every context by inject-memory.sh
#   MEMORY-CATALOG.md  ON-DEMAND  — read by the recall command, never auto-injected
#
# Never hand-edit either file. Edit a memory's `name:` / `description:` frontmatter, or add a
# memory, and re-run. Context injected into every prompt is the scarcest resource here, which
# is the whole reason for the split: standing behavioural rules stay resident; project and
# reference memories are POINTERS, pulled in only when a topic arises.
#
#   bash engine/rebuild-index.sh            # operates on ${CLAUDE_CONFIG_DIR:-~/.claude}/memory
#   RAEMEMBERIT_MEMORY_DIR=/path bash ...        # or an explicit corpus
set -euo pipefail
. "$(dirname "$0")/lib/raememberit-root.sh"
cd "$RAEMEMBERIT_MEM" || { echo "rebuild-index: no corpus at $RAEMEMBERIT_MEM" >&2; exit 1; }

RECENT_N="${RAEMEMBERIT_RECENT_N:-8}"   # how many latest interaction logs to surface

get_name() { awk 'NR<=6 && /^name:/{sub(/^name:[ ]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
get_desc() {
  local d
  d=$(awk 'NR<=15 && /^description:/{sub(/^description:[ ]*/,""); gsub(/^"|"$/,""); print; exit}' "$1")
  [ -n "$d" ] && { echo "$d"; return; }
  awk '/^---[ ]*$/{fm++; next} fm==1{next} /^#/{sub(/^#+[ ]*/,""); print; exit} NF{print; exit}' "$1"
}
# A non-matching glob makes `ls` exit non-zero, and under `set -o pipefail` that aborts the
# whole generation — which is precisely the EMPTY-CORPUS case, i.e. every fresh install. The
# SessionEnd hook wraps this script in `|| true`, so such a failure is completely silent: a
# truncated MEMORY.md and no catalog at all, with no error anywhere. `find` succeeds on an
# empty directory, so it is used for every listing and count below.
list_md()  { find "$1" -maxdepth 1 -name '*.md' 2>/dev/null; }
count_md() { list_md "$1" | wc -l | tr -d ' '; }
# Absent scope means `global` — see the rationale in mem-write.sh. Defaulting the other way
# would empty the always-on tier on the first rebuild after this change lands.
get_scope() { awk 'NR<=20 && /^  scope:/{sub(/^  scope:[ ]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
get_domain() { awk 'NR<=20 && /^  domain:/{sub(/^  domain:[ ]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }

# THE DOMAIN INDEX. A third derived file, `.domain-index`, tab-separated: domain, path, name,
# description — one row per (domain, memory). It is what lets a prompt-time hook surface memories
# for the repo or tool a task names without opening every file. Only memories that declare
# `metadata.domain:` appear in it; the catalog line also shows the domain, so `/recall`'s grep
# catches it too. Written alongside the two indexes, staged the same way.
T_DOM=""
emit_domain_rows() {  # $1 = file, $2 = name, $3 = desc
  local d; d=$(get_domain "$1"); [ -n "$d" ] || return 0
  printf '%s\n' "$d" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | while read -r tok; do
    [ -n "$tok" ] && printf '%s\t%s\t%s\t%s\n' "$tok" "$1" "$2" "$3" >> "$T_DOM"
  done
}
line_for() {  # $1 = file, $2 = with-domain (1 in the catalog, 0 in the always-on tier)
  local nm ds d; nm=$(get_name "$1"); [ -z "$nm" ] && nm=$(basename "$1" .md); ds=$(get_desc "$1")
  d=""; [ "${2:-0}" = 1 ] && d=$(get_domain "$1")
  if [ -n "$d" ]; then printf -- '- [%s](%s) — %s · domain: %s\n' "$nm" "$1" "$ds" "$d"
  else                 printf -- '- [%s](%s) — %s\n' "$nm" "$1" "$ds"; fi
  [ -n "$T_DOM" ] && emit_domain_rows "$1" "$nm" "$ds"
  return 0
}

emit_scoped() {  # $1 = section title, $2 = dir, $3 = wanted scope, $4 = with-domain
  printf '\n## %s\n' "$1"
  for f in "$2"/*.md; do
    [ -e "$f" ] || continue
    local sc; sc=$(get_scope "$f"); [ -z "$sc" ] && sc=global
    [ "$sc" = "$3" ] || continue
    line_for "$f" "${4:-0}"
  done
}

emit() {  # $1 = section title, $2 = dir, $3 = with-domain
  printf '\n## %s\n' "$1"
  for f in "$2"/*.md; do
    [ -e "$f" ] || continue
    line_for "$f" "${3:-0}"
  done
}

# THE SECOND SILO, LISTED. Claude Code keeps its own auto-memory under <config>/projects/<cwd>/memory/,
# keyed by working directory and owned by the harness. It was findable only by a glob inside /recall,
# which every other retrieval path ignored. Listing it in the ON-DEMAND catalog — read-only, never
# written, never scored — makes it one grep away like everything else. It stays out of the always-on
# tier: those stores can be large and are not this corpus's to budget.
emit_native() {
  local base f store any=0
  for base in "$RAEMEMBERIT_CONFIG"/projects/*/memory; do
    [ -d "$base" ] || continue
    for f in "$base"/*.md; do
      [ -e "$f" ] || continue
      [ "$any" = 0 ] && { printf '\n## Native auto-memory — owned by Claude Code, read-only, keyed by working directory\n'; any=1; }
      store=$(basename "$(dirname "$base")")
      printf -- '- [%s/%s](%s) — %s\n' "$store" "$(basename "$f" .md)" "$f" "$(get_desc "$f")"
    done
  done
  return 0
}

# STAGED, NOT REDIRECTED. `{ ... } > MEMORY.md` truncates the file the instant it opens, so any
# failure part-way through generation leaves a HALF-WRITTEN index and no error — the same silent
# corruption this script's own header warns about for empty corpora. Render to temps, validate,
# then mv (atomic within one filesystem).
T_IDX=$(mktemp "$RAEMEMBERIT_MEM/.MEMORY.md.XXXXXX")
T_CAT=$(mktemp "$RAEMEMBERIT_MEM/.MEMORY-CATALOG.md.XXXXXX")
T_DOMTMP=$(mktemp "$RAEMEMBERIT_MEM/.domain-index.XXXXXX")
trap 'rm -f "$T_IDX" "$T_CAT" "$T_DOMTMP"' EXIT

# BUDGET, not a prediction. The harness ceiling is undocumented and moves: the smallest payload seen
# truncated was 15,493 B on 2026-09-27, then 10,291 B on 2026-09-30 — while a 9,317 B payload had
# been delivered two days earlier. So the ceiling sat somewhere just above 9.3 KB that day, and the
# old 12,000 B default was above it. This is a MARGIN target that keeps the payload under any ceiling
# seen so far; detecting an actual truncation is hooks/truncation-tripwire.sh's job, from the
# artifacts the harness writes, and that is what caught the move.
BUDGET="${RAEMEMBERIT_ALWAYS_ON_BUDGET:-8000}"

# ---- ALWAYS-ON ----------------------------------------------------------------------
{
  echo "# Memory Index"
  echo "<!-- AUTO-GENERATED by engine/rebuild-index.sh — do not hand-edit; edit frontmatter and re-run. -->"
  echo ""
  [ -f user_profile.md ] && printf -- '- [user-profile](user_profile.md) — %s\n' "$(get_desc user_profile.md)"
  emit_scoped "Feedback" feedback global
  printf '\n## Recent work (latest %s interaction logs)\n' "$RECENT_N"
  list_md interactions | sort -r | head -"$RECENT_N" | while read -r f; do
    printf -- '- [%s](%s) — %s\n' "$(basename "$f" .md)" "$f" "$(get_desc "$f")"
  done
  printf '\n## On-demand catalog — NOT loaded here\n'
  printf -- '%s project + %s reference memories are indexed in `MEMORY-CATALOG.md`.\n' \
    "$(count_md project)" "$(count_md reference)"
  printf 'When a task touches a repo, ticket, tool or environment not already in context, search\n'
  printf 'that catalog BEFORE investigating from scratch. Assume a relevant memory exists until\n'
  printf 'the catalog says otherwise.\n'
} > "$T_IDX"

# ---- ON-DEMAND ---------------------------------------------------------------------
{
  echo "# Memory Catalog (on-demand)"
  echo "<!-- AUTO-GENERATED by engine/rebuild-index.sh. Read on demand, NOT injected per prompt. -->"
  T_DOM="$T_DOMTMP"
  emit_scoped "Feedback (domain-scoped — demoted from always-on)" feedback domain 1
  emit "Project"   project 1
  emit "Reference" reference 1
  T_DOM=""
  # ARCHIVE. Until now nothing read this directory: not the indexes, not /recall. Memories moved
  # there became unreachable by every documented retrieval path, which makes "archive" a quiet
  # delete rather than a filing. Listing it in the ON-DEMAND catalog keeps finished work findable
  # and visibly finished, at no cost to the always-on tier.
  #
  # It stays out of the eval's corpus (DIRS = feedback/project/reference) on purpose: archived work
  # should not be scored for retrieval quality, only remain reachable when someone looks for it.
  emit "Archive — finished work, kept for the record" archive
  emit_native

  printf '\n## All interaction logs\n'
  printf 'Full session history lives in `interactions/` (%s files), named\n' \
    "$(count_md interactions)"
  printf '`YYYY-MM-DD-HH-MM-topic.md`. Grep the directory by topic keyword.\n'
} > "$T_CAT"

mv "$T_IDX" MEMORY.md
mv "$T_CAT" MEMORY-CATALOG.md
mv "$T_DOMTMP" .domain-index
trap - EXIT

SZ=$(wc -c < MEMORY.md | tr -d ' ')
echo "MEMORY.md:         $(grep -c '^- \[' MEMORY.md || true) entries, $SZ bytes (always-on)"
echo "MEMORY-CATALOG.md: $(grep -c '^- \[' MEMORY-CATALOG.md || true) entries, $(wc -c < MEMORY-CATALOG.md | tr -d ' ') bytes (on-demand)"

# The index is ALWAYS installed, even over budget: a stale or missing index is worse than a large
# one. The verdict goes to a status file because the SessionEnd hook runs this with stderr
# redirected to a log — a bare `exit 1` there would be as silent as the bug it reports. The
# SessionStart tripwire reads this file and surfaces it where it can actually be seen.
if [ "$SZ" -gt "$BUDGET" ]; then
  printf 'OVER %s %s\n' "$SZ" "$BUDGET" > "$RAEMEMBERIT_MEM/.index-status"
  printf 'rebuild-index: always-on index is %s bytes, over the %s-byte budget — demote feedback memories with `metadata.scope: domain`\n' "$SZ" "$BUDGET" >&2
  exit 1
fi
printf 'OK %s %s\n' "$SZ" "$BUDGET" > "$RAEMEMBERIT_MEM/.index-status"
