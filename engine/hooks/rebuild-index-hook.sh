#!/usr/bin/env bash
# SessionEnd — regenerate the indexes from frontmatter so they never drift from the files.
set -uo pipefail
. "$(dirname "$0")/../lib/memkit-root.sh"
bash "$(dirname "$0")/../rebuild-index.sh" >/dev/null 2>&1 || true
exit 0
