#!/usr/bin/env bash
# Remove raememberit from a Claude Code config dir.
#
#   ./uninstall.sh                          # from ${CLAUDE_CONFIG_DIR:-~/.claude}
#   ./uninstall.sh --config-dir ~/x/.claude
#   ./uninstall.sh --purge                  # ALSO delete the corpus (asks first)
#   ./uninstall.sh --dry-run
#
# By DEFAULT your memories are kept. Removing the tooling should never cost you the notes you
# wrote with it — and a pilot nobody can back out of cleanly is a pilot nobody should agree to.
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
    --config-dir) TARGET="${2:?}"; shift 2 ;;
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
[ -n "$MEM" ] || MEM="$(dirname "$TARGET")/raememberit-memory"

say "Tooling"
run rm -rf "$TARGET/raememberit"
for c in recall learn memory-reflect memory-audit skill-mine; do
  [ -f "$TARGET/commands/$c.md" ] && run rm -f "$TARGET/commands/$c.md"
done
ok "engine and commands removed"

say "Settings"
if [ -f "$TARGET/settings.json" ] && [ "$DRY" = 0 ]; then
python3 - "$TARGET/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
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
        perm[k] = [r for r in perm[k] if "raememberit-memory" not in r]
        rules += before - len(perm[k])
        if not perm[k]: del perm[k]
if not perm: d.pop("permissions", None)
env = d.get("env", {})
envs = 1 if env.pop("RAEMEMBERIT_MEMORY_DIR", None) else 0
if not env: d.pop("env", None)
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
print(f"  \033[1;32m✓\033[0m {removed} hook group(s), {rules} permission rule(s) and {envs} env entry removed; "
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
  printf '    Plain markdown — readable and greppable with this tool gone. Delete it yourself,\n'
  printf '    or re-run with --purge, if you truly want it gone.\n'
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
