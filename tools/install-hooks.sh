#!/usr/bin/env bash
# Install raememberit's git hooks into this clone.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
install -m 0755 "$ROOT/tools/pre-commit" "$ROOT/.git/hooks/pre-commit"
echo "installed .git/hooks/pre-commit -> tools/sanitize-scan.sh --staged"
