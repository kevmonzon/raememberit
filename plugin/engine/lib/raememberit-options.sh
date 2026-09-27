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
# THE CASING IS NOT FULLY KNOWN — and this is deliberate rather than lazy. Across the 39 official
# plugins only ONE option is ever read (`telemetry` -> CLAUDE_PLUGIN_OPTION_TELEMETRY), which is a single
# word, so how a camelCase key like `memoryDir` is spelled — MEMORYDIR or MEMORY_DIR — is unevidenced.
# Guessing would fail silently: a wrong name reads empty and the default takes over, which looks exactly
# like working. So both spellings are accepted. Settle it by observing a real session, then simplify.

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
__rmi_take RAEMEMBERIT_MEMORY_DIR    MEMORYDIR MEMORY_DIR
__rmi_take RAEMEMBERIT_DUPES         DUPES
__rmi_take RAEMEMBERIT_REQUIRE_LOG   REQUIRELOG REQUIRE_LOG
__rmi_take RAEMEMBERIT_PRECOMPACT_MSG PRECOMPACTMESSAGE PRECOMPACT_MESSAGE
__rmi_take RAEMEMBERIT_RECENT_N      RECENTN RECENT_N
__rmi_take RAEMEMBERIT_PERSONA_FILE  PERSONAFILE PERSONA_FILE
__rmi_take RAEMEMBERIT_VOCAB_FILE    VOCABULARYFILE VOCABULARY_FILE

unset -f __rmi_take
