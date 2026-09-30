#!/usr/bin/env bash
# Remove raememberit from a Claude Code config dir.
#
#   ./uninstall.sh                          # from ${CLAUDE_CONFIG_DIR:-~/.claude}
#   ./uninstall.sh --config-dir ~/x/.claude
#   ./uninstall.sh --purge                  # ALSO delete the corpus (asks first)
#   ./uninstall.sh --dry-run
#
# By DEFAULT your memories are kept. Removing the tooling should never cost you the notes you
# wrote with it — and a tool nobody can back out of cleanly is a tool nobody should adopt.
#
# What it removes: the engine, the installed commands, this tool's hook entries, its permission
# rules and its env entry. Your own hooks, rules and settings are left untouched.
set -euo pipefail

TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PURGE=0; DRY=0
say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) TARGET="${2:?}"; TARGET_EXPLICIT=1; shift 2 ;;
    --purge)      PURGE=1; shift ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,16p' "$0"; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

say "Target"; ok "$TARGET"
[ -d "$TARGET" ] || { warn "no such config dir — nothing to do"; exit 0; }

# resolve the corpus the same way everything else does, so we report the right path
MEM="${RAEMEMBERIT_MEMORY_DIR:-}"
if [ -z "$MEM" ] && [ -f "$TARGET/settings.json" ]; then
  MEM=$(jq -r '.env.RAEMEMBERIT_MEMORY_DIR // empty' "$TARGET/settings.json" 2>/dev/null || true)
fi
[ -n "$MEM" ] || MEM="$TARGET/memory"

# A flag the caller typed beats a variable the environment happened to carry. install.sh has had
# this rule since an ambient RAEMEMBERIT_MEMORY_DIR redirected a --config-dir install onto a live
# corpus; the fix was never carried across to here, where the stakes are strictly higher. Uninstall
# only REPORTS the corpus by default — but --purge deletes what this variable resolves to, so an
# ambient value could offer to erase a corpus the caller never named.
if [ "${TARGET_EXPLICIT:-0}" = 1 ] && [ -n "${RAEMEMBERIT_MEMORY_DIR:-}" ]; then
  case "$RAEMEMBERIT_MEMORY_DIR" in
    "$TARGET"/*) : ;;   # inside the named config dir: consistent, keep it
    *) warn "ignoring RAEMEMBERIT_MEMORY_DIR=$RAEMEMBERIT_MEMORY_DIR"
       warn "  --config-dir $TARGET was given explicitly, and that variable points outside it."
       warn "  Using $TARGET/memory. An ambient variable must not redirect an explicitly targeted uninstall."
       MEM="$TARGET/memory" ;;
  esac
fi

say "Tooling"
run rm -rf "$TARGET/raememberit"
for c in recall learn memory-reflect memory-audit skill-mine; do
  [ -f "$TARGET/commands/$c.md" ] && run rm -f "$TARGET/commands/$c.md"
done
ok "engine and commands removed"
# THE PLUGIN DIRECTORY. Two of the three install routes put the hooks in <config>/skills/raememberit/
# and nothing in settings.json. This script stripped settings and removed the engine — and left that
# directory behind, so nine hooks kept firing every session at a path that no longer existed. Measured
# 2026-09-30 on both routes. Remove it, but only when its manifest says it is ours: a directory with
# that name and someone else's manifest is theirs.
SK="$TARGET/skills/raememberit"
if [ -f "$SK/.claude-plugin/plugin.json" ]; then
  if jq -e '.name == "raememberit"' "$SK/.claude-plugin/plugin.json" >/dev/null 2>&1; then
    run rm -rf "$SK"
    ok "plugin directory removed — its hooks would otherwise keep firing at the removed engine"
  else
    warn "$SK exists but its manifest is not raememberit's — left alone"
  fi
fi

say "Settings"
if [ -f "$TARGET/settings.json" ] && [ "$DRY" = 0 ]; then
python3 - "$TARGET/settings.json" "$MEM" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); mem = sys.argv[2]
MARK = "/raememberit/engine/hooks/"
hooks = d.get("hooks", {}); removed = 0
for ev in list(hooks):
    before = len(hooks[ev])
    hooks[ev] = [g for g in hooks[ev]
                 if not any(MARK in (h.get("command") or "") for h in g.get("hooks", []))]
    removed += before - len(hooks[ev])
    if not hooks[ev]: del hooks[ev]
if not hooks: d.pop("hooks", None)
perm = d.get("permissions", {}); rules = 0
for k in ("allow", "deny", "ask"):
    if k in perm:
        before = len(perm[k])
        # Only OUR rules: anything naming raememberit, and the one Read() rule aimed at THIS corpus.
        # `"/memory/**" not in r` used to go too, which would have taken a user's own rule on some
        # other memory directory with it.
        perm[k] = [r for r in perm[k] if "raememberit" not in r and r != f"Read({mem}/**)"]
        rules += before - len(perm[k])
        if not perm[k]: del perm[k]
if not perm: d.pop("permissions", None)
# Every knob, not only the corpus path: a leftover RAEMEMBERIT_REQUIRE_LOG=strict or DUPES=block is
# inert once the engine is gone, but it is litter that looks like configuration.
env = d.get("env", {})
envs = 0
for k in [k for k in env if k.startswith("RAEMEMBERIT_")]:
    env.pop(k); envs += 1
if not env: d.pop("env", None)
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
print(f"  \033[1;32m✓\033[0m {removed} hook group(s), {rules} permission rule(s) and {envs} env entr{"y" if envs == 1 else "ies"} removed; "
      f"everything else left as it was")
PY
else
  [ "$DRY" = 1 ] && printf '  would: strip hook groups, permission rules and the env entry\n'
fi

say "Corpus"
if [ ! -d "$MEM" ]; then ok "no corpus at $MEM"
elif [ "$PURGE" = 0 ]; then
  N=$(find "$MEM" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  ok "KEPT: $N file(s) at $MEM"
  printf '    Plain markdown, inside your config directory — readable and greppable with this tool\n'
  printf '    gone, and it travels with the rest of your config. Delete it yourself, or re-run with\n'
  printf '    --purge, if you truly want it gone.\n'
else
  N=$(find "$MEM" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  warn "--purge will permanently delete $N file(s) at $MEM"
  if [ "$DRY" = 1 ]; then printf '  would: delete %s\n' "$MEM"
  else
    printf '  Type exactly DELETE to confirm: '
    read -r reply
    if [ "$reply" = "DELETE" ]; then rm -rf "$MEM"; ok "corpus deleted"
    else warn "not confirmed — corpus kept"; fi
  fi
fi

say "Done"
printf '  Remove the fragment reference from your CLAUDE.md if you added one.\n'
