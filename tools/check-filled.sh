#!/usr/bin/env bash
# Verify an INSTALLED tree has no template slots left unfilled.
#
#   tools/check-filled.sh <installed-dir>
#
# This check is deliberately NOT part of the commit gate: the kit repo is supposed to contain
# {{SLOT}} markers. A slot only becomes a defect once it has been installed, which is where a
# colleague would meet it as literal "{{USER}}" in their own commands.
set -euo pipefail
T="${1:?usage: check-filled.sh <installed-dir>}"
hits=$(grep -rInE '\{\{[A-Z_]+\}\}' "$T" 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "unfilled template slots in $T:" >&2
  printf '%s\n' "$hits" | sed 's/^/  /' >&2
  exit 1
fi
echo "no unfilled slots in $T"
