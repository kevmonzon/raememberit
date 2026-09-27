#!/usr/bin/env bash
# Bridge a plugin's userConfig options onto the RAEMEMBERIT_* names the engine already reads.
# Sourced by raememberit-root.sh, so every hook and script gets it. Do not execute.
#
# WHY A BRIDGE AND NOT A REWRITE. The engine has read RAEMEMBERIT_* since before there was a plugin,
# the standalone install sets those through settings `env`, and a plugin CANNOT declare `env` at all
# (measured: 0 of 39 official manifests). So the two routes supply configuration by different means and
# the engine should not have to know which one it is running under. One mapping here; nothing else changes.
#
# PRECEDENCE: an explicit RAEMEMBERIT_* wins over a plugin option. A standalone user set it on purpose,
# and a plugin-only user has none of them set, so this favours the deliberate over the default without
# ever fighting itself.
#
# THE CASING, SETTLED. Read out of the Claude Code 2.1.274 binary rather than inferred — the official
# marketplace reads exactly one option anywhere and it is a single word, so no plugin demonstrates what
# happens to a camelCase key. The construction is:
#
#     key.replace(/[^A-Za-z0-9_]/g, "_").toUpperCase()   ->  CLAUDE_PLUGIN_OPTION_<that>
#
# Non-alphanumerics become underscores and the whole thing is uppercased. camelCase boundaries are NOT
# split. So `memoryDir` is CLAUDE_PLUGIN_OPTION_MEMORYDIR — never MEMORY_DIR. This matters because a
# wrong name here fails OPEN: it reads empty, the default takes over, and nothing looks broken.
#
# (There is a second route: a hook command may interpolate ${user_config.<key>} directly. Not used here
# — the engine reads its configuration from the environment, and one mechanism is enough.)

# take VAR OPTION_SUFFIX_A [OPTION_SUFFIX_B] — set VAR only if it is currently unset or empty.
__rmi_take() {
  local var="$1"; shift
  eval "local cur=\"\${$var:-}\""
  [ -z "$cur" ] || return 0
  local suffix val
  for suffix in "$@"; do
    eval "val=\"\${CLAUDE_PLUGIN_OPTION_${suffix}:-}\""
    if [ -n "$val" ]; then
      eval "$var=\"\$val\""
      eval "export $var"
      return 0
    fi
  done
  return 0
}

__rmi_take RAEMEMBERIT_USER          USER
__rmi_take RAEMEMBERIT_MEMORY_DIR    MEMORYDIR
__rmi_take RAEMEMBERIT_DUPES         DUPES
__rmi_take RAEMEMBERIT_REQUIRE_LOG   REQUIRELOG
__rmi_take RAEMEMBERIT_PRECOMPACT_MSG PRECOMPACTMESSAGE
__rmi_take RAEMEMBERIT_RECENT_N      RECENTN
__rmi_take RAEMEMBERIT_PERSONA_FILE  PERSONAFILE
__rmi_take RAEMEMBERIT_VOCAB_FILE    VOCABULARYFILE

unset -f __rmi_take
