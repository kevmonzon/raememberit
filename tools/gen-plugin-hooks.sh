#!/usr/bin/env bash
# SUPERSEDED by tools/build-plugin.sh, which generates the whole plugin tree — engine, hooks and
# manifest — rather than the hooks alone. Kept as a delegating alias so existing habits and any
# out-of-tree caller keep working.
set -euo pipefail
exec bash "$(dirname "$0")/build-plugin.sh"
