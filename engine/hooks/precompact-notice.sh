#!/usr/bin/env bash
# PreCompact — remind the assistant to capture durable memory before context compresses.
set -uo pipefail
jq -n '{"systemMessage":"Context is compacting — capture the interaction log and any durable memories now, before they compress away."}'
exit 0
