#!/usr/bin/env bash
# Emit the hook table as markdown, read from engine/settings.fragment.json.
#
# WHY GENERATED: in the setup this kit was extracted from, the hand-written hook table
# documented a SessionStart hook that existed in no settings file, and a guard-file claim that
# had flipped three times across three audits because each one read the previous audit's prose
# instead of the file. Documentation of wiring must be derived from the wiring.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/engine/settings.fragment.json"
[ -f "$F" ] || { echo "gen-hook-table: missing $F" >&2; exit 1; }
printf '| Event | Matcher | Script | Timeout |\n|---|---|---|---|\n'
jq -r '
  .hooks | to_entries[] as $e
  | $e.value[] as $grp
  | $grp.hooks[]
  | "| `\($e.key)` | \(if ($grp.matcher // "") == "" then "_(all)_" else "`" + $grp.matcher + "`" end) | `\(.command | sub(".*/hooks/"; ""))` | \(.timeout // "-")s |"
' "$F"
