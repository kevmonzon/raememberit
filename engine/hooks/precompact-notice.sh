#!/usr/bin/env bash
# PreCompact — remind the assistant to capture durable memory before context compresses.
#
# $RAEMEMBERIT_PRECOMPACT_MSG overrides the wording. The message is the entire content of this hook,
# and an adopted setup may well have phrasing of its own worth keeping — a persona, a house term, a
# pointer to local conventions. Editing this file would not survive an upgrade, because install.sh
# replaces the whole engine directory; an env var set in settings.json does.
set -uo pipefail
DEFAULT="Context is compacting — capture the interaction log and any durable memories now, before they compress away."
jq -n --arg m "${RAEMEMBERIT_PRECOMPACT_MSG:-$DEFAULT}" '{"systemMessage":$m}'
exit 0
