#!/usr/bin/env bash
# Shared root resolution for every memkit hook and script. Source it; do not execute it.
#
# WHY THIS EXISTS: `CLAUDE_CONFIG_DIR` relocates Claude Code's whole config, but it does NOT
# change $HOME. So a hook that hardcodes ~/.claude/memory keeps writing the DEFAULT corpus
# even when the session is pointed at a sandbox — which makes an "isolated" test quietly
# mutate the real thing. Verified 2026-09-27: hooks DO inherit CLAUDE_CONFIG_DIR, so this
# expression is both correct and sufficient.
#
#   MEMKIT_CONFIG  the active Claude Code config dir
#   MEMKIT_MEM     the corpus root inside it
MEMKIT_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MEMKIT_MEM="${MEMKIT_MEMORY_DIR:-$MEMKIT_CONFIG/memory}"
export MEMKIT_CONFIG MEMKIT_MEM
