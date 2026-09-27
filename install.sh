#!/usr/bin/env bash
# raememberit installer. Safe to re-run: it upgrades in place and never overwrites your corpus.
#
#   ./install.sh                                   # into ${CLAUDE_CONFIG_DIR:-~/.claude}
#   ./install.sh --profile example --user Alex
#   ./install.sh --config-dir ~/sandbox/.claude    # a throwaway target
#   ./install.sh --dry-run                         # say what would change, change nothing
#   ./install.sh --force                           # also replace an existing corpus scaffold
#
# It will NOT:
#   - touch credentials, or any *.local.json
#   - overwrite an existing memory/ corpus without --force
#   - replace your settings file — hooks are MERGED, and re-merging replaces only raememberit's own
#
# bash 3.2 compatible (macOS /bin/bash). Derived from a single-user bootstrap script that had
# already solved the boring parts: check jq, leave credentials alone, rebuild the index at the end.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROFILE="default"; USERNAME=""; FORCE=0; DRY=0

say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) TARGET="${2:?}"; shift 2 ;;
    --profile)    PROFILE="${2:?}"; shift 2 ;;
    --user)       USERNAME="${2:?}"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *)            die "unknown option: $1" ;;
  esac
done

# ── preflight ───────────────────────────────────────────────────────────────────────
say "Preflight"
command -v jq      >/dev/null 2>&1 || die "jq is required (hooks parse their stdin with it). brew install jq"
command -v python3 >/dev/null 2>&1 || die "python3 is required (settings merge, eval harness)"
ok "jq $(jq --version 2>/dev/null) · python3 $(python3 -V 2>&1 | cut -d' ' -f2)"
[ -d "$SRC/engine" ] || die "run this from a raememberit checkout (no engine/ next to install.sh)"

# ── resolve the profile ─────────────────────────────────────────────────────────────
say "Profile"
if [ -d "$PROFILE" ]; then PDIR="$PROFILE"
elif [ -d "$SRC/profiles/$PROFILE" ]; then PDIR="$SRC/profiles/$PROFILE"
else die "no such profile: $PROFILE (try: default, example, or a path)"
fi
# NOTE: profiles set RAEMEMBERIT_USER, never USER. USER is a standard environment variable, so a
# profile that simply omitted it would leave the shell's own USER in scope and this installer
# would silently write the system username into every installed command.
PUSER=""
if [ -f "$PDIR/profile.env" ]; then
  RAEMEMBERIT_USER=""
  # shellcheck disable=SC1090
  . "$PDIR/profile.env"
  PUSER="${RAEMEMBERIT_USER:-}"
fi
[ -n "$USERNAME" ] && PUSER="$USERNAME"
[ -n "$PUSER" ] || PUSER="you"
ok "$(basename "$PDIR") · addressee \"$PUSER\""
[ -f "$PDIR/persona.md" ] && ok "persona supplied" || ok "no persona (default)"

# ── target ──────────────────────────────────────────────────────────────────────────
say "Target"
ok "$TARGET"
[ "$TARGET" = "$SRC" ] && die "refusing to install into the checkout itself"
run mkdir -p "$TARGET/raememberit" "$TARGET/commands"

# ── engine ──────────────────────────────────────────────────────────────────────────
say "Engine"
run rm -rf "$TARGET/raememberit/engine"
run cp -R "$SRC/engine" "$TARGET/raememberit/engine"
run cp "$SRC/tools/check-filled.sh" "$TARGET/raememberit/"
ok "engine/ installed (hooks resolve via \${CLAUDE_CONFIG_DIR:-\$HOME/.claude})"

# ── commands: fill the slot ─────────────────────────────────────────────────────────
say "Corpus"
# The corpus is a SIBLING of the config dir, not inside it. Measured reason: Claude Code treats any
# path inside a `.claude` directory as a sensitive file needing per-file approval, and an explicit
# Edit() allow rule does NOT override that gate — tested, still refused. An in-config corpus means a
# permission prompt on every single memory write for anyone not running an auto-approve mode. An
# existing in-config corpus is honoured, so nobody's files are moved by an upgrade.
if [ -n "${RAEMEMBERIT_MEMORY_DIR:-}" ]; then
  MEM="$RAEMEMBERIT_MEMORY_DIR"; ok "corpus location from \$RAEMEMBERIT_MEMORY_DIR"
elif [ -n "$(find "$TARGET/memory/feedback" "$TARGET/memory/project" "$TARGET/memory/reference" \
                  -name '*.md' 2>/dev/null | head -1 || true)" ]; then
  MEM="$TARGET/memory"
  warn "using the existing in-config corpus at $MEM"
  warn "note: writes there need per-file approval unless you run an auto-approve mode — that is a"
  warn "      Claude Code sensitive-path rule, not a raememberit setting. Move it out and set"
  warn "      RAEMEMBERIT_MEMORY_DIR to avoid the prompts."
else
  MEM="$(dirname "$TARGET")/raememberit-memory"; ok "corpus at $MEM (outside the config dir, on purpose)"
fi
FRESH=0
# "Existing corpus" means actual MEMORIES, not the generated indexes or the scaffold README. A
# directory holding only MEMORY.md is a half-initialised install, and it still needs its starter
# rules — counting generated files as content would silently skip them forever.
# `find` on a directory that does not exist yet exits non-zero, and under `set -o pipefail` that
# would abort the installer — the same trap that once made the index generator die on an empty
# corpus. Hence the `|| true`.
HAVE=$(find "$MEM/feedback" "$MEM/project" "$MEM/reference" -name '*.md' 2>/dev/null | head -1 || true)
if [ -n "$HAVE" ]; then
  if [ "$FORCE" = 1 ]; then warn "existing corpus at $MEM — --force given, scaffold will be topped up (memories are never deleted)"
  else warn "existing corpus at $MEM — left completely alone. Pass --force to top up missing scaffold."; fi
else
  FRESH=1; ok "no existing corpus — scaffolding a fresh one"
fi
if [ "$FRESH" = 1 ] || [ "$FORCE" = 1 ]; then
  for d in feedback project reference interactions archive artifacts eval; do run mkdir -p "$MEM/$d"; done
  [ -f "$MEM/README.md" ]   || run cp "$SRC/scaffold/memory/README.md" "$MEM/README.md"
  if [ "$DRY" = 1 ]; then printf '  would: install user_profile.md and starter rules\n'; else
    [ -f "$MEM/user_profile.md" ] || sed "s/{{USER}}/$PUSER/g" "$SRC/starter/user_profile.md" > "$MEM/user_profile.md"
    for f in "$SRC/starter/feedback"/*.md; do
      [ -e "$f" ] || continue
      [ -f "$MEM/feedback/$(basename "$f")" ] || cp "$f" "$MEM/feedback/"
    done
    for f in "$PDIR/feedback"/*.md; do
      [ -e "$f" ] || continue
      [ -f "$MEM/feedback/$(basename "$f")" ] || cp "$f" "$MEM/feedback/"
    done
    [ -f "$MEM/eval/queries.json" ] || cp "$SRC/starter/queries.json" "$MEM/eval/queries.json"
  fi
  ok "scaffold, starter rules and eval queries in place (existing files never replaced)"
fi
[ -f "$PDIR/vocabulary.txt" ] && run cp "$PDIR/vocabulary.txt" "$TARGET/raememberit/vocabulary.txt"

say "Commands"
n=0
for t in "$SRC/protocol"/*.md.tmpl; do
  [ -e "$t" ] || continue
  b="$(basename "$t" .tmpl)"
  if [ "$DRY" = 1 ]; then printf '  would: install commands/%s\n' "$b"; else
    # {{MEM}} is filled with the RESOLVED corpus path, not an expression the command has to
    # re-derive. A command that re-derives it drifts the moment the resolution rule changes — which
    # it did once, and the stale snippet then greps the wrong directory and reports a confident
    # "no prior memory".
    sed -e "s/{{USER}}/$PUSER/g" -e "s|{{MEM}}|$MEM|g" \
        -e "s|engine/|$TARGET/raememberit/engine/|g" "$t" > "$TARGET/commands/$b"
  fi
  n=$((n+1))
done
ok "$n command(s) installed with the addressee filled in"

# ── corpus ──────────────────────────────────────────────────────────────────────────
# ── instructions fragment ───────────────────────────────────────────────────────────
say "Instructions"
FRAG="$TARGET/raememberit/INSTRUCTIONS-fragment.md"
if [ "$DRY" = 1 ]; then printf '  would: write %s\n' "$FRAG"; else
  cp "$SRC/starter/INSTRUCTIONS-fragment.md" "$FRAG"
  if [ -f "$PDIR/persona.md" ]; then { printf '\n'; cat "$PDIR/persona.md"; } >> "$FRAG"; fi
fi
ok "fragment written — it is YOURS to paste into CLAUDE.md; nothing was written to your CLAUDE.md"

# ── hooks: merge, never replace ─────────────────────────────────────────────────────
say "Hooks"
if [ "$DRY" = 1 ]; then printf '  would: merge hook wiring into %s/settings.json\n' "$TARGET"; else
python3 - "$SRC/engine/settings.fragment.json" "$TARGET/settings.json" "$MEM" <<'PY'
import json, os, sys
frag_p, set_p, mem = sys.argv[1], sys.argv[2], sys.argv[3]
frag = json.load(open(frag_p))
cur  = json.load(open(set_p)) if os.path.exists(set_p) else {}
hooks = cur.setdefault("hooks", {})
MARK = "/raememberit/engine/hooks/"

def is_ours(group):
    return any(MARK in (h.get("command") or "") for h in group.get("hooks", []))

replaced = added = kept = 0
for ev, groups in frag["hooks"].items():
    existing = hooks.get(ev, [])
    mine  = [g for g in existing if is_ours(g)]
    yours = [g for g in existing if not is_ours(g)]
    kept += len(yours); replaced += len(mine)
    # yours first: your hooks keep their relative order and are never dropped
    hooks[ev] = yours + groups
    added += len(groups)

# Publish the corpus path so hooks, the eval harness and the assistant's own shell all agree on
# one location without anyone having to remember a flag.
env = cur.setdefault("env", {})
env["RAEMEMBERIT_MEMORY_DIR"] = mem

# And allow editing it without a prompt per file. This works only because the corpus is OUTSIDE
# the config dir; the same rule aimed inside a `.claude` path is refused by the sensitive-file gate.
perm  = cur.setdefault("permissions", {})
allow = perm.setdefault("allow", [])
new_rules = 0
for r in (f"Edit({mem}/**)", f"Read({mem}/**)"):
    if r not in allow:
        allow.append(r); new_rules += 1

json.dump(cur, open(set_p, "w"), indent=2); open(set_p, "a").write("\n")
print(f"  \033[1;32m✓\033[0m {added} raememberit hook group(s) wired · "
      f"{replaced} previous raememberit group(s) replaced · {kept} of your own hook group(s) preserved")
print(f"  \033[1;32m✓\033[0m corpus path published as env.RAEMEMBERIT_MEMORY_DIR · "
      f"{new_rules} permission rule(s) added so memory writes do not prompt")
PY
fi

# ── index + verification ────────────────────────────────────────────────────────────
say "Index"
if [ "$DRY" = 1 ]; then printf '  would: rebuild the indexes and verify\n'; else
  CLAUDE_CONFIG_DIR="$TARGET" RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$TARGET/raememberit/engine/rebuild-index.sh" | sed 's/^/  /'
  bash "$SRC/tools/check-filled.sh" "$TARGET/commands" | sed 's/^/  ✓ /'
  CLAUDE_CONFIG_DIR="$TARGET" RAEMEMBERIT_MEMORY_DIR="$MEM" python3 "$TARGET/raememberit/engine/eval/run_eval.py" --health \
    | sed -n '1p' | sed 's/^/  /'
fi

say "Done"
cat <<EOF
  Next:
    1. Paste $TARGET/raememberit/INSTRUCTIONS-fragment.md into your CLAUDE.md (or reference it).
    2. Your first /learn may ask permission to write outside the working directory. That is
       correct behaviour on a fresh install, not a fault — grant this config dir once.
    3. Try it:  /learn something you just worked out   then   /recall that topic
  Re-run this installer any time; it upgrades in place and never touches your memories.
EOF
