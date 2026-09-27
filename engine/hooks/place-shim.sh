#!/usr/bin/env bash
# SessionStart — place the write helper at a STABLE path, and keep it pointing at the current version.
#
# THE PROBLEM THIS SOLVES. A plugin is installed at
#     ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>
# which carries a VERSION component. A permission rule must name an absolute path, so a rule aimed at
# the helper inside the plugin would be invalidated by every single update — and a user who has to
# re-approve after each update will instead approve nothing and get a prompt on every memory write.
#
# There is a version-free path in the same tree: $CLAUDE_PLUGIN_DATA, which resolves to
#     ~/.claude/plugins/data/<plugin>-<marketplace>/
# Measured present for every installed plugin here, read by claude-security from inside a hook, and
# written to by code-modernization. So it is a supported, writable, stable state directory.
#
# WHY A WRAPPER AND NOT A COPY. Every engine script finds its siblings with $(dirname "$0") — the
# property that lets the engine live anywhere. A COPY of mem-write.sh in the data dir would therefore
# look for lib/, rebuild-index.sh and eval/ IN THE DATA DIR and find none of them. So this places a
# two-line wrapper that execs the real helper, with the current plugin root baked in.
#
# Regenerated on every session start, which is what makes it self-healing: after an update the root
# changes, the next session rewrites the wrapper, and the permission rule never moves.
set -euo pipefail

# Not running as a plugin (standalone install) — the engine is already at a stable path. Nothing to do.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || exit 0

target_dir="$CLAUDE_PLUGIN_DATA/bin"
target="$target_dir/mem-write.sh"
real="$CLAUDE_PLUGIN_ROOT/engine/mem-write.sh"

[ -f "$real" ] || exit 0

# MEASURED 2026-09-27: `claude plugin update` KEEPS the previous version directory, so a wrapper not
# yet rewritten keeps working — one engine version behind, silently, until the next SessionStart. That
# is benign. What would not be benign is the target being GONE (a future cleanup, a manual rm): the
# wrapper would fail with a bare "No such file or directory" and nothing would say why. So it checks.
want="#!/usr/bin/env bash
# GENERATED each session by raememberit's place-shim.sh hook. Do not edit.
# Stable path for the permission rule; the versioned plugin root lives on the next line only.
real=\"$real\"
if [ ! -f \"\$real\" ]; then
  printf 'raememberit: the plugin version this shim points at is gone:\\n  %s\\nStart a new session — the SessionStart hook repoints this file automatically.\\n' \"\$real\" >&2
  exit 1
fi
exec bash \"\$real\" \"\$@\""

# Idempotent: rewrite only when the content actually differs, so an unchanged session touches nothing.
if [ ! -f "$target" ] || [ "$(cat "$target")" != "$want" ]; then
  mkdir -p "$target_dir"
  printf '%s\n' "$want" > "$target"
  chmod +x "$target" 2>/dev/null || true
fi
exit 0
