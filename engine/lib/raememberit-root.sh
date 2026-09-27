#!/usr/bin/env bash
# Shared root resolution for every raememberit hook and script. Source it; do not execute it.
#
#   RAEMEMBERIT_CONFIG  the active Claude Code config dir
#   RAEMEMBERIT_MEM     the corpus root
#
# WHY CLAUDE_CONFIG_DIR AND NOT ~/.claude: CLAUDE_CONFIG_DIR relocates the whole config, but it
# does NOT change $HOME. A hook hardcoding ~/.claude keeps writing the DEFAULT corpus even when the
# session is pointed at a sandbox, which makes an "isolated" test quietly mutate the real thing.
# Verified: hooks DO inherit CLAUDE_CONFIG_DIR, so this expression is correct and sufficient.
#
# WHY THE CORPUS IS NOT INSIDE THE CONFIG DIR — measured, not preference:
#   Claude Code classifies any path inside a `.claude` directory as a SENSITIVE FILE and requires
#   per-file approval to write it. An explicit `Edit(<config>/memory/**)` allow rule does NOT
#   override that gate; tested, still refused. So a corpus inside the config dir means a permission
#   prompt on EVERY memory write for anyone not running in an auto-approve mode — which is most
#   people, and certainly anyone on a fresh install. The corpus therefore lives in a SIBLING of the
#   config dir, which keeps it isolated per-config-dir (so sandboxes still work) without being
#   inside `.claude`.
#
# Resolution order:
#   1. $RAEMEMBERIT_MEMORY_DIR                  explicit override, always wins
#   2. <config>/memory                     LEGACY layout, used only if it already holds memories
#   3. <config-parent>/raememberit-memory       the default for a new install
RAEMEMBERIT_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${RAEMEMBERIT_MEMORY_DIR:-}" ]; then
  RAEMEMBERIT_MEM="$RAEMEMBERIT_MEMORY_DIR"
elif [ -n "$(find "$RAEMEMBERIT_CONFIG/memory/feedback" "$RAEMEMBERIT_CONFIG/memory/project" \
                  "$RAEMEMBERIT_CONFIG/memory/reference" -name '*.md' 2>/dev/null | head -1 || true)" ]; then
  RAEMEMBERIT_MEM="$RAEMEMBERIT_CONFIG/memory"        # respect an existing in-config corpus
else
  RAEMEMBERIT_MEM="$(dirname "$RAEMEMBERIT_CONFIG")/raememberit-memory"
fi
export RAEMEMBERIT_CONFIG RAEMEMBERIT_MEM
