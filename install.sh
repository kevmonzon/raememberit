#!/usr/bin/env bash
# raememberit installer. Safe to re-run: it upgrades in place and never overwrites your corpus.
#
#   ./install.sh                                   # into ${CLAUDE_CONFIG_DIR:-~/.claude}
#   ./install.sh --user Alex --persona ~/my-voice.md
#   ./install.sh --config-dir ~/sandbox/.claude    # a throwaway target
#   ./install.sh --dry-run                         # say what would change, change nothing
#   ./install.sh --guided | --no-guided            # walk me through it / just install
#   ./install.sh --plugin                          # plugin already ships engine+hooks: corpus,
#                                                  # permission rule and fragment only
#   ./install.sh --as-plugin                       # place plugin/ at <config>/skills/raememberit/
#                                                  # too — the plugin route, no marketplace needed
#   ./install.sh --hooks-from-plugin               # engine in the config dir (so anything pointing at
#                                                  # it keeps working), hooks from a generated plugin
#
# GUIDED MODE is on by default for a fresh interactive install and off otherwise (a re-run, or
# no terminal). It is the onboarding: someone who has to read a document first is someone who
# starts late or not at all. It pauses at each step that changes something, shows what it is
# about to do, and never writes to your CLAUDE.md unasked.
#   ./install.sh --force                           # also top up an existing corpus scaffold
#   ./install.sh --force-commands                  # also overwrite commands YOU have edited
#   ./install.sh --replace-plugin                  # also replace a plugin directory YOU have edited
#
# --force, --force-commands and --replace-plugin are deliberately SEPARATE. Conflating them would mean
# that topping up a scaffold silently discards command customizations — or, as it once did, that the
# only way to upgrade the plugin route also re-seeded starter rules into a corpus that had deleted them.
# One flag, one irreversible thing.
#
# It will NOT:
#   - touch credentials, or any *.local.json
#   - overwrite an existing memory/ corpus without --force
#   - overwrite a command you have edited, ever, without --force-commands
#   - replace your settings file — hooks are MERGED, and re-merging replaces only raememberit's own
#
# bash 3.2 compatible (macOS /bin/bash). Derived from a single-user bootstrap script that had
# already solved the boring parts: check jq, leave credentials alone, rebuild the index at the end.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET_EXPLICIT=0   # set when --config-dir names a target, which then outranks ambient variables
USERNAME=""; PERSONA=""; VOCAB=""; FORCE=0; FORCECMD=0; REPLACEPLUGIN=0; DRY=0; GUIDED=auto; PLUGINMODE=0; ASPLUGIN=0; HFP=0
SHIM=""   # in --plugin mode, the discovered stable path of the write helper

say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

# ── guided-mode plumbing ───────────────────────────────────────────────────────────────
interactive() { [ -t 0 ] && [ -t 1 ]; }
step()  { printf '\n\033[1m── %s\033[0m\n' "$*"; }
note()  { printf '   %s\n' "$*"; }
pause() { # only ever pauses when someone is actually there to read it
  [ "$GUIDED" = 1 ] || return 0
  interactive || return 0
  [ -r /dev/tty ] || return 0
  printf '\n   \033[2m[Enter to continue]\033[0m '; read -r _ </dev/tty || true; printf '\n'
}
confirm() { # confirm "question"  -> 0 yes, 1 no. Non-interactive answers yes, and says so.
  if [ "$GUIDED" != 1 ] || ! interactive || [ ! -r /dev/tty ]; then return 1; fi
  printf '   %s [y/N] ' "$1"; read -r r </dev/tty || r=n
  case "$r" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# Predecessor memory hooks: the case that silently doubles everything. Detected by what they
# reference, because that is the only reliable signature — names and comments vary.
find_predecessor_hooks() {
  local f found=""
  for f in "$TARGET/settings.json" "$TARGET/settings.local.json"; do
    [ -f "$f" ] || continue
    found="$found$(jq -r '
      (.hooks // {}) | to_entries[] | .key as $ev | .value[]? | .hooks[]? | .command // ""
      | select(test("memory/MEMORY\\.md|memory/rebuild-index|memory/interactions"))
      | select(test("raememberit") | not)
      | "\($ev)"' "$f" 2>/dev/null)
"
  done
  printf '%s' "$found" | grep -v '^$' | sort -u
}

# Fingerprint of a plugin tree, PATH-RELATIVE so the source tree and a placed copy compare equal.
# The record file itself and Finder droppings are excluded, or the copy could never match its source.
PLACEMARK=".raememberit-placed"
plugin_fp() { (cd "$1" && find . -type f ! -name "$PLACEMARK" ! -name '.DS_Store' | sort | xargs shasum 2>/dev/null | shasum | awk '{print $1}'); }

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) TARGET="${2:?}"; TARGET_EXPLICIT=1; shift 2 ;;
    --user)       USERNAME="${2:?}"; shift 2 ;;
    --persona)    PERSONA="${2:?}"; shift 2 ;;
    --vocabulary) VOCAB="${2:?}"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    --force-commands) FORCECMD=1; shift ;;
    --replace-plugin) REPLACEPLUGIN=1; shift ;;
    --dry-run)    DRY=1; shift ;;
    --guided)     GUIDED=1; shift ;;
    --no-guided)  GUIDED=0; shift ;;
    # --plugin: the plugin already ships the engine, the commands and the hooks, so this does ONLY
    # the parts a plugin cannot do for itself — seed the corpus, add the one permission rule, offer the
    # instruction fragment. Same script, same guided flow, no second implementation to drift.
    --plugin)     PLUGINMODE=1; shift ;;
    # --as-plugin: PLACE the plugin as well, at <config>/skills/raememberit/, which auto-loads as
    # raememberit@skills-dir with no settings entry at all. This is the plugin route without a
    # marketplace: distribution is this script, and the install path carries NO version, so the write
    # helper needs no wrapper — the rule can name the engine directly and still never move.
    --as-plugin)  PLUGINMODE=1; ASPLUGIN=1; shift ;;
    # --hooks-from-plugin: the THIRD arrangement, and the one an adopted setup actually ends up in.
    # The engine stays in the config dir — anything referencing it keeps working, which matters because
    # hand-edited commands hardcode those paths — while the HOOKS come from a small generated plugin
    # instead of from settings.json. Everything else is the standalone route unchanged.
    --hooks-from-plugin) HFP=1; shift ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *)            die "unknown option: $1" ;;
  esac
done

# ── preflight ───────────────────────────────────────────────────────────────────────
say "Preflight"
command -v jq      >/dev/null 2>&1 || die "jq is required (hooks parse their stdin with it). brew install jq"
command -v python3 >/dev/null 2>&1 || die "python3 is required (settings merge, eval harness)"
ok "jq $(jq --version 2>/dev/null) · python3 $(python3 -V 2>&1 | cut -d' ' -f2)"

# auto: guide a fresh interactive install; stay quiet for a re-run or a non-terminal
if [ "$GUIDED" = auto ]; then
  if interactive && [ ! -d "$TARGET/raememberit" ]; then GUIDED=1; else GUIDED=0; fi
fi
[ -d "$SRC/engine" ] || die "run this from a raememberit checkout (no engine/ next to install.sh)"

# ── who this is for, and two optional files ────────────────────────────────────────
# There used to be a "profile" mechanism here: named bundles supplying an addressee, a persona, a
# vocabulary and extra rules. It was built, documented, tested — and used by nobody, because one
# person's configuration is a handful of VALUES, not a bundle. Values are what this takes now.
say "Configuration"
# WHY THESE ARE REMEMBERED. This installer tells you to re-run it any time, and it upgrades in place. But
# --user, --persona and --vocabulary were only ever read from the command line, so a re-run WITHOUT them
# silently re-rendered every command with the default addressee and dropped the persona from the
# instruction fragment. Measured: `--user Testee` then a bare re-run rewrote "Testee" to "you" in two
# commands and reported it only as "2 updated". The cause — a forgotten flag — was invisible.
#
# So the chosen values are recorded, and a re-run that does not name them inherits them. An explicitly
# passed flag still wins, which is how you change your mind.
CFGFILE="$TARGET/raememberit/.config"
cfgget() { [ -f "$CFGFILE" ] || return 0; sed -n "s|^$1=||p" "$CFGFILE" | tail -1; }

REMEMBERED_USER="$(cfgget user)"
REMEMBERED_PERSONA="$(cfgget persona)"
REMEMBERED_VOCAB="$(cfgget vocabulary)"

if [ -n "$USERNAME" ]; then PUSER="$USERNAME"; USERSRC="given"
elif [ -n "$REMEMBERED_USER" ]; then PUSER="$REMEMBERED_USER"; USERSRC="remembered from the last run"
else PUSER="you"; USERSRC="default"; fi
# A REMEMBERED path that has since vanished must not be fatal. A GIVEN one must: naming a file that is
# not there is a typo, and guessing past it would install something other than what was asked for. But
# inheriting a stale path and dying on it would wedge the installer PERMANENTLY — the record keeps the
# bad path, so every future run fails the same way and the remedy is invisible. Warn, drop, carry on.
if [ -z "$PERSONA" ] && [ -n "$REMEMBERED_PERSONA" ]; then
  if [ -f "$REMEMBERED_PERSONA" ]; then PERSONA="$REMEMBERED_PERSONA"
  else warn "remembered persona file is gone, ignoring it: $REMEMBERED_PERSONA"; fi
fi
if [ -z "$VOCAB" ] && [ -n "$REMEMBERED_VOCAB" ]; then
  if [ -f "$REMEMBERED_VOCAB" ]; then VOCAB="$REMEMBERED_VOCAB"
  else warn "remembered vocabulary file is gone, ignoring it: $REMEMBERED_VOCAB"; fi
fi
ok "addressee \"$PUSER\" ($USERSRC)"
if [ -n "$PERSONA" ]; then
  [ -f "$PERSONA" ] || die "no such persona file: $PERSONA"
  ok "persona from $PERSONA"
else
  ok "no persona (the default)"
fi
if [ -n "$VOCAB" ]; then
  [ -f "$VOCAB" ] || die "no such vocabulary file: $VOCAB"
  ok "recall vocabulary from $VOCAB"
fi

# ── target ──────────────────────────────────────────────────────────────────────────
if [ "$GUIDED" = 1 ]; then
  step "What this is about to do"
  note "raememberit is a memory discipline: two commands you will use daily (learn, recall), a few"
  note "hooks that make capture involuntary, and a corpus of plain markdown you own."
  note ""
  note "Everything lands inside $TARGET, so your config stays one copy-pasteable unit."
  note "Nothing is written to your CLAUDE.md. Your memories are never overwritten."
  note "To undo all of it later:  ./uninstall.sh   (your memories are kept by default)"
  pause

  step "What I found"
  if [ -d "$TARGET/raememberit" ]; then note "· raememberit is already installed here — this is an upgrade"
  else note "· no previous install"; fi
  if [ -n "$(find "$TARGET/memory/feedback" "$TARGET/memory/project" "$TARGET/memory/reference" -name '*.md' 2>/dev/null | head -1 || true)" ]
  then note "· an existing memory corpus — it will be left completely alone"
  else note "· no corpus yet — I will scaffold one and seed some starter rules"; fi
  PRED=$(find_predecessor_hooks || true)
  if [ -n "$PRED" ]; then
    printf '\n'
    warn "You already have memory hooks of your own on: $(printf '%s' "$PRED" | tr '\n' ' ')"
    note "  Those will keep running ALONGSIDE the ones I add, which means double work:"
    note "  the index injected twice, a session-end marker written twice, and so on."
    note "  I do not remove them, because I cannot tell a hook you want from one I am replacing."
    note "  After this finishes, compare them and drop whichever you do not want."
  else
    note "· no memory hooks of your own to collide with"
  fi
  pause
fi

say "Target"
ok "$TARGET"
[ "$TARGET" = "$SRC" ] && die "refusing to install into the checkout itself"
# Plugin mode owns neither directory: the engine is in the plugin and the commands are namespaced,
# so creating an empty raememberit/ and commands/ here would just leave litter.
if [ "$PLUGINMODE" = 1 ]; then run mkdir -p "$TARGET"; else run mkdir -p "$TARGET/raememberit" "$TARGET/commands"; fi

# ── engine ──────────────────────────────────────────────────────────────────────────
say "Engine"
if [ "$ASPLUGIN" = 1 ]; then
  SKILLDIR="$TARGET/skills/raememberit"
  [ -d "$SRC/plugin" ] || die "no plugin/ next to install.sh — run tools/build-plugin.sh first"
  # THE SAME FOUR-STATE POLICY THE COMMANDS GET, because the plugin directory had the worse half of it.
  # It refused to clobber an existing directory — right, someone may have edited it — but that made a
  # re-run a NO-OP for everyone who had not, and "re-run to upgrade" quietly stopped being true on this
  # route. Measured 2026-09-30: a marker planted in the placed engine survived the documented upgrade.
  # The escape hatch was --force, which ALSO tops up the corpus scaffold, so upgrading the plugin
  # re-seeded starter rules a corpus had deliberately deleted. So: a fingerprint of what was placed is
  # recorded inside the directory, and the four cases separate:
  #   absent                                   -> place
  #   identical to the source                  -> current (and record it, if a pre-record install)
  #   matches the record — ours, untouched     -> update
  #   differs from the record, or no record    -> SKIP, and say so; --replace-plugin overrides
  PLACED=0
  NEWFP=$(plugin_fp "$SRC/plugin")
  if [ ! -d "$SKILLDIR" ]; then paction=place
  else
    CURFP=$(plugin_fp "$SKILLDIR")
    RECFP=$(cat "$SKILLDIR/$PLACEMARK" 2>/dev/null || true)
    if   [ "$CURFP" = "$NEWFP" ];       then paction=current
    elif [ "$REPLACEPLUGIN" = 1 ];      then paction=replace
    elif [ -z "$RECFP" ];               then paction=skip-unknown
    elif [ "$CURFP" = "$RECFP" ];       then paction=update
    else                                     paction=skip-edited
    fi
  fi
  case "$paction" in
    place|update|replace)
      run rm -rf "$SKILLDIR"
      run mkdir -p "$(dirname "$SKILLDIR")"
      run cp -R "$SRC/plugin" "$SKILLDIR"
      [ "$DRY" = 1 ] || printf '%s\n' "$NEWFP" > "$SKILLDIR/$PLACEMARK"
      PLACED=1
      case "$paction" in
        place)   ok "plugin placed at $SKILLDIR (auto-loads as raememberit@skills-dir; no settings entry needed)" ;;
        update)  ok "plugin at $SKILLDIR was ours and untouched — updated to this version" ;;
        replace) warn "--replace-plugin given: replaced $SKILLDIR, discarding whatever was there" ;;
      esac ;;
    current)
      PLACED=1
      ok "plugin at $SKILLDIR is already this version"
      # A directory placed before this record existed, still byte-identical to the source, is
      # provably untouched — record it now so the NEXT upgrade flows without a flag.
      [ "$DRY" = 1 ] || [ -f "$SKILLDIR/$PLACEMARK" ] || printf '%s\n' "$NEWFP" > "$SKILLDIR/$PLACEMARK" ;;
    skip-edited)
      warn "$SKILLDIR — YOU edited this since it was placed; left alone."
      warn "  Pass --replace-plugin to take the shipped version instead (your edits would be lost)." ;;
    skip-unknown)
      warn "$SKILLDIR exists and was not placed by this installer (or predates the record); left alone."
      warn "  Pass --replace-plugin to replace it with the shipped version." ;;
  esac

  # A skills-dir install has NO version component in its path, so the wrapper that exists for the
  # marketplace case is unnecessary here: name the engine itself and the rule still never moves.
  #
  # BUT VERIFY IT EXISTS FIRST. An earlier version of this branch set SHIM unconditionally and reported
  # it as fact. Against a config holding an OLDER raememberit plugin — one from before the engine was
  # shipped inside the plugin — that named a file which was not there, and the permission rule went in
  # anyway. A rule naming a nonexistent path grants nothing and fails SILENTLY: memory writes simply
  # begin prompting, with nothing anywhere to say why. Exactly the fail-open shape this kit keeps
  # tripping over, so the check is the fix and the refusal is the point.
  CAND="$SKILLDIR/engine/mem-write.sh"
  if [ "$DRY" = 1 ] && [ "$PLACED" = 1 ]; then
    SHIM="$CAND"
    ok "write helper would be $SHIM (stable by construction — no version in the path)"
  elif [ -f "$CAND" ]; then
    SHIM="$CAND"
    ok "write helper: $SHIM (stable by construction — no version in the path)"
  else
    SHIM=""
    warn "no write helper at $CAND"
    warn ""
    warn "$SKILLDIR exists but ships no engine/. That is a raememberit plugin from before the engine"
    warn "was shipped inside it — or it is not a raememberit plugin at all. Either way there is nothing"
    warn "to point a permission rule at, and adding one anyway would grant nothing while looking fine:"
    warn "every memory write would just start prompting."
    warn ""
    warn "  ./install.sh --as-plugin --replace-plugin    replace it with the current plugin"
    warn ""
    warn "If that directory is deliberate — a plugin supplying hooks while the engine lives in the"
    warn "config dir — then --as-plugin is the wrong route for this setup and would move the engine"
    warn "out from under anything referencing it."
    die  "refusing to add a permission rule for a helper that does not exist."
  fi
elif [ "$PLUGINMODE" = 1 ]; then
  ok "skipped — the plugin ships its own engine at \${CLAUDE_PLUGIN_ROOT}/engine"
  # The permission rule must name an absolute path, and the plugin's own path carries a VERSION, so a
  # rule aimed there dies on the next update. place-shim.sh puts a wrapper at the version-free
  # $CLAUDE_PLUGIN_DATA/bin/ on every SessionStart — so DISCOVER it rather than guessing the
  # <plugin>-<marketplace> directory name, which is exactly the kind of guess that fails silently.
  SHIM=$(find "$TARGET/plugins/data" -maxdepth 3 -path '*/bin/mem-write.sh' 2>/dev/null | head -1 || true)
  if [ -n "$SHIM" ]; then
    ok "write helper at the stable path: $SHIM"
  else
    warn "no write helper at $TARGET/plugins/data/*/bin/mem-write.sh yet."
    warn "That file is placed by the plugin's SessionStart hook, so it appears after ONE restart."
    warn "Everything else below still applies; re-run this with --plugin afterwards to add the rule."
  fi
else
  run rm -rf "$TARGET/raememberit/engine"
  run cp -R "$SRC/engine" "$TARGET/raememberit/engine"
  run cp "$SRC/tools/check-filled.sh" "$TARGET/raememberit/"
  ok "engine/ installed (hooks resolve via \${CLAUDE_CONFIG_DIR:-\$HOME/.claude})"
fi

# Record the choices so the next run inherits them rather than silently reverting to defaults.
if [ "$DRY" = 1 ]; then printf '  would: record the addressee and optional file paths in %s\n' "$CFGFILE"
elif [ -d "$TARGET/raememberit" ]; then
  { printf 'user=%s\n' "$PUSER"
    [ -n "$PERSONA" ] && printf 'persona=%s\n' "$PERSONA"
    [ -n "$VOCAB" ]   && printf 'vocabulary=%s\n' "$VOCAB"; } > "$CFGFILE"
fi

# ââ the hooks-only plugin ââââââââââââââââââââââââââââââââââ
# WHY THIS NEEDS NO REWRITING AT ALL, and why that makes the mode cheap: the settings fragment's commands
# are ALREADY ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/raememberit/engine/hooks/... , which is exactly where
# this mode leaves the engine. So hooks.json is the fragment's own hooks, verbatim. Nothing is
# transformed, so nothing can be transformed wrongly â and because it is generated here from the single
# fragment rather than committed, there is no third tree to drift.
#
# It ships NO userConfig. Configuration here arrives through settings `env`, which the options bridge
# gives precedence over any option â so a declared option would be silently shadowed, and a knob that
# turns nothing is worse than no knob. Same reason the manifest does not pretend to declare `permissions`.
#
# And NO place-shim: the engine's path here carries no version, so that wrapper would be a moving part
# solving a problem this mode does not have.
if [ "$HFP" = 1 ]; then
  say "Hooks plugin"
  SKILLDIR="$TARGET/skills/raememberit"
  if [ "$DRY" = 1 ]; then
    printf '  would: generate %s/{.claude-plugin/plugin.json,hooks/hooks.json} from the settings fragment\n' "$SKILLDIR"
    [ -d "$SKILLDIR" ] && printf '  would: REPLACE the generated files in the existing %s\n' "$SKILLDIR"
  else
    mkdir -p "$SKILLDIR/.claude-plugin" "$SKILLDIR/hooks"
    python3 "$SRC/tools/gen-hooks-only-plugin.py" "$SRC/engine/settings.fragment.json" "$SKILLDIR"
    ok "loads as raememberit@skills-dir with no settings entry; no engine, no commands, no options inside"
  fi
fi

# ── commands: fill the slot ─────────────────────────────────────────────────────────
say "Corpus"
# INSIDE the config dir, deliberately: the whole directory stays one portable, copy-pasteable unit.
# The cost is that Claude Code treats paths inside a `.claude` directory as sensitive files that the
# Edit/Write tools refuse per file — an Edit() allow rule does NOT override it. Engineered around
# rather than accepted: writes go through engine/mem-write.sh over Bash, which is not gated, and one
# Bash() allow rule below covers it. Reads are not gated at all.
# AN EXPLICIT --config-dir MUST OUTRANK AN AMBIENT RAEMEMBERIT_MEMORY_DIR.
#
# It did not, and the consequence was as bad as it sounds: once that variable was published into a real
# settings.json, every `--config-dir /tmp/sandbox` run silently operated on the corpus the variable named.
# Test suites believed they were isolated while seeding and re-indexing the live corpus; one run with
# --force copied a starter rule into it. Measured 2026-09-28.
#
# lib/raememberit-root.sh carries a comment warning about exactly this shape — "which makes an 'isolated'
# test quietly mutate the real thing" — and the installer had the bug anyway. Reading a warning is not the
# same as applying it.
#
# The rule: a flag the caller typed beats a variable the environment happened to carry. Env still wins
# when no --config-dir was given, which is how a published corpus path keeps working.
MEM="${RAEMEMBERIT_MEMORY_DIR:-$TARGET/memory}"
if [ "$TARGET_EXPLICIT" = 1 ] && [ -n "${RAEMEMBERIT_MEMORY_DIR:-}" ]; then
  case "$RAEMEMBERIT_MEMORY_DIR" in
    "$TARGET"/*) : ;;   # inside the named config dir: consistent, keep it
    *) warn "ignoring RAEMEMBERIT_MEMORY_DIR=$RAEMEMBERIT_MEMORY_DIR"
       warn "  --config-dir $TARGET was given explicitly, and that variable points outside it."
       warn "  Using $TARGET/memory. An ambient variable must not redirect an explicitly targeted install."
       MEM="$TARGET/memory" ;;
  esac
fi
ok "corpus at $MEM"
FRESH=0        # must be initialised: `set -u` aborts on the existing-corpus path otherwise
HAVE=$(find "$MEM/feedback" "$MEM/project" "$MEM/reference" -name '*.md' 2>/dev/null | head -1 || true)
if [ -n "$HAVE" ]; then
  if [ "$FORCE" = 1 ]; then warn "existing corpus at $MEM — --force given, scaffold will be topped up (memories are never deleted)"
  else warn "existing corpus at $MEM — left completely alone. Pass --force to top up missing scaffold."; fi
else
  FRESH=1; ok "no existing corpus — scaffolding a fresh one"
fi
# A DELETED STARTER RULE STAYS DELETED. Topping up used to copy in every shipped starter that was
# absent, which cannot tell "never seeded" from "deleted on purpose" — and a starter someone removed
# came back on the next --force, uninvited, into the always-on tier. So the corpus keeps a record of
# which starters were ever seeded into it (.seeded-starters, one name per line). A name in the record
# is a decision already taken, present or not; only a starter NOT in the record — one that shipped
# after this corpus was seeded — is added.
#
# A corpus with NO record predates this. Its missing starters are undecidable, so none are added:
# every shipped name is recorded as decided, and the installer says how to add one by hand. Adding
# silently was the defect; asking someone to copy one file is not.
SEEDREC="$MEM/.seeded-starters"
if [ "$FRESH" = 1 ] || [ "$FORCE" = 1 ]; then
  for d in feedback project reference interactions archive artifacts eval; do run mkdir -p "$MEM/$d"; done
  [ -f "$MEM/README.md" ]   || run cp "$SRC/scaffold/memory/README.md" "$MEM/README.md"
  if [ "$DRY" = 1 ]; then printf '  would: install user_profile.md and starter rules (respecting %s)\n' "$SEEDREC"; else
    [ -f "$MEM/user_profile.md" ] || sed "s/{{USER}}/$PUSER/g" "$SRC/starter/user_profile.md" > "$MEM/user_profile.md"
    seeded=0; skipped_deleted=0
    if [ "$FRESH" = 0 ] && [ ! -f "$SEEDREC" ]; then
      warn "no seed record at $SEEDREC — this corpus predates it, so a missing starter rule cannot be"
      warn "  told apart from one you deleted. None added. Want one? cp $SRC/starter/feedback/<name>.md $MEM/feedback/"
      for f in "$SRC/starter/feedback"/*.md; do [ -e "$f" ] && basename "$f" .md; done > "$SEEDREC"
    else
      touch "$SEEDREC"
      for f in "$SRC/starter/feedback"/*.md; do
        [ -e "$f" ] || continue
        nm=$(basename "$f" .md)
        if grep -qx "$nm" "$SEEDREC"; then
          [ -f "$MEM/feedback/$nm.md" ] || skipped_deleted=$((skipped_deleted+1))
          continue
        fi
        [ -f "$MEM/feedback/$nm.md" ] || { cp "$f" "$MEM/feedback/"; seeded=$((seeded+1)); }
        printf '%s\n' "$nm" >> "$SEEDREC"
      done
    fi
    [ "$skipped_deleted" -gt 0 ] && ok "$skipped_deleted starter rule(s) you deleted stay deleted"
    [ -f "$MEM/eval/queries.json" ] || cp "$SRC/starter/queries.json" "$MEM/eval/queries.json"
  fi
  ok "scaffold, starter rules and eval queries in place (existing files never replaced)"
fi
[ -n "$VOCAB" ] && run cp "$VOCAB" "$TARGET/raememberit/vocabulary.txt"

say "Commands"
if [ "$PLUGINMODE" = 1 ]; then
  ok "skipped — the plugin ships its own, namespaced /raememberit:<name>"
  note "Your own /learn and /recall, if you have them, keep their names and are untouched."
else
# A command may have been customized locally — the whole point of adopting this into an existing setup
# is that the text can be YOURS. So the installer distinguishes three cases using a manifest of what
# it wrote last time (raememberit/.installed-commands):
#
#   absent                     -> install
#   matches what we wrote      -> ours, untouched: safe to update
#   differs from what we wrote -> YOU edited it: SKIP, and say so
#   no manifest entry at all   -> unknown provenance: SKIP, conservatively
#
# Without the manifest the only safe policy would be "never update", which would strand everyone on
# whatever version they first installed. With it, upgrades flow to untouched files and stop at edited
# ones, which is the behaviour a package manager has for config files and for the same reason.
MANIFEST="$TARGET/raememberit/.installed-commands"
n=0; skipped=0; updated=0; unchanged=0
[ "$DRY" = 0 ] && : > "$MANIFEST.new"
for t in "$SRC/protocol"/*.md.tmpl; do
  [ -e "$t" ] || continue
  b="$(basename "$t" .tmpl)"
  dest="$TARGET/commands/$b"
  rendered="${TMPDIR:-/tmp}/rmb-render.$$"
  sed -e "s/{{USER}}/$PUSER/g" -e "s|{{MEM}}|$MEM|g" \
      -e "s|engine/|$TARGET/raememberit/engine/|g" "$t" > "$rendered"
  newsum=$(shasum "$rendered" | cut -d' ' -f1)

  if [ ! -e "$dest" ]; then
    action=install
  else
    cursum=$(shasum "$dest" | cut -d' ' -f1)
    recorded=$(grep " $b\$" "$MANIFEST" 2>/dev/null | cut -d' ' -f1 || true)
    if [ "$cursum" = "$newsum" ];        then action=current
    elif [ -z "$recorded" ];             then action=skip-unknown
    elif [ "$cursum" = "$recorded" ];    then action=update
    else                                      action=skip-edited
    fi
  fi

  case "$action" in
    install|update)
      if [ "$DRY" = 1 ]; then printf '  would: %s commands/%s\n' "$action" "$b"
      else cp "$rendered" "$dest"; printf '%s %s\n' "$newsum" "$b" >> "$MANIFEST.new"; fi
      [ "$action" = update ] && updated=$((updated+1)) || n=$((n+1)) ;;
    current)
      # Counted, not silent. "0 installed · 0 updated · 2 left alone" on a config holding five commands
      # is a report that does not add up, and a reader cannot tell whether the other three were touched.
      unchanged=$((unchanged+1))
      [ "$DRY" = 0 ] && printf '%s %s\n' "$newsum" "$b" >> "$MANIFEST.new" ;;
    skip-edited)
      # Save the version we WOULD have written, so the comparison is a runnable command rather than a
      # suggestion. A warning you cannot act on is only noise.
      if [ "$DRY" = 0 ]; then
        mkdir -p "$TARGET/raememberit/shipped"; cp "$rendered" "$TARGET/raememberit/shipped/$b"
      fi
      warn "commands/$b — YOU edited this; left alone"
      printf '      diff %s %s\n' "$TARGET/raememberit/shipped/$b" "$dest"
      skipped=$((skipped+1))
      # keep the old record so the file stays recognised as edited on the next run
      [ "$DRY" = 0 ] && { r=$(grep " $b\$" "$MANIFEST" 2>/dev/null || true); [ -n "$r" ] && printf '%s\n' "$r" >> "$MANIFEST.new"; } ;;
    skip-unknown)
      warn "commands/$b — already present and not written by this installer; left alone"
      skipped=$((skipped+1)) ;;
  esac
  rm -f "$rendered"
done
if [ "$FORCECMD" = 1 ] && [ "$skipped" -gt 0 ]; then
  warn "--force-commands given: overwriting the $skipped skipped command(s)"
  for t in "$SRC/protocol"/*.md.tmpl; do
    b="$(basename "$t" .tmpl)"
    if [ "$DRY" = 1 ]; then printf '  would: overwrite commands/%s\n' "$b"; else
      sed -e "s/{{USER}}/$PUSER/g" -e "s|{{MEM}}|$MEM|g" \
          -e "s|engine/|$TARGET/raememberit/engine/|g" "$t" > "$TARGET/commands/$b"
      shasum "$TARGET/commands/$b" | sed "s| .*| $b|" >> "$MANIFEST.new"
    fi
  done
  n=$((n+skipped)); skipped=0
fi
[ "$DRY" = 0 ] && mv "$MANIFEST.new" "$MANIFEST"
ok "commands: $n installed · $updated updated · $unchanged already current · $skipped left alone (yours)"
[ "$skipped" -gt 0 ] && printf '    Your edits are kept. Pass --force-commands to take the shipped versions instead.\n'
fi

# ── instructions fragment ───────────────────────────────────────────────────────────
say "Instructions"
# In plugin mode there is no $TARGET/raememberit/ to put it in — the engine lives in the plugin, which
# is replaced on update, so a file the user is meant to read and keep cannot live there.
if [ "$PLUGINMODE" = 1 ]; then FRAG="$MEM/INSTRUCTIONS-fragment.md"; else FRAG="$TARGET/raememberit/INSTRUCTIONS-fragment.md"; fi
if [ "$DRY" = 1 ]; then printf '  would: write %s\n' "$FRAG"; else
  cp "$SRC/starter/INSTRUCTIONS-fragment.md" "$FRAG"
  if [ -n "$PERSONA" ]; then { printf '\n'; cat "$PERSONA"; } >> "$FRAG"; fi
fi
ok "fragment written — it is YOURS to paste into CLAUDE.md; nothing was written to your CLAUDE.md"

# THE STEP THAT LOOKS LIKE SUCCESS AND ISN'T. Pasting the fragment is manual, on purpose — this
# installer does not edit anyone's CLAUDE.md. But skip it and every hook still fires, the corpus is
# still written, the indexes still rebuild, and nothing ever tells Claude the corpus exists. An
# install that reports seven green steps and then does nothing is the exact failure mode this kit was
# built to detect elsewhere; it should not ship one of its own.
#
# ASK THE RIGHT QUESTION. A first version of this grepped for "raememberit" — the kit's own name —
# and therefore fired on every adopted setup, which is the arrangement this installer is FOR: someone
# who read the fragment and wrote the instructions in their own words, naming /learn and /recall and
# their corpus rather than the tool. A warning that cries wolf on the recommended configuration is
# worse than no warning, because it trains the reader to skip it. What matters is not whether the
# fragment was pasted but whether SOMETHING tells Claude a corpus exists.
if [ "$DRY" != 1 ]; then
  FRAG_SEEN=0
  for c in "$TARGET/CLAUDE.md" "$PWD/CLAUDE.md"; do
    [ -f "$c" ] || continue
    if grep -qiE 'raememberit|/learn|/recall|^#+[[:space:]].*\bmemor' "$c" 2>/dev/null \
       || grep -qF "$MEM" "$c" 2>/dev/null; then FRAG_SEEN=1; break; fi
  done
  if [ "$FRAG_SEEN" = 0 ]; then
    warn "no CLAUDE.md here mentions a memory corpus — until one does, the hooks run but"
    warn "  nothing tells Claude to use it. Checked $TARGET/CLAUDE.md and ./CLAUDE.md;"
    warn "  if yours lives elsewhere, this warning is the only thing that is wrong."
  else
    ok "a CLAUDE.md already instructs Claude about a memory corpus"
  fi
fi

# ── hooks: merge, never replace ─────────────────────────────────────────────────────
say "Hooks"
# The mirror image of the case plugin mode strips: a standalone install wires seven hook groups into
# settings, and a plugin sitting at <config>/skills/raememberit supplies the same ones. Nothing errors;
# it just doubles. Name it rather than let it be discovered.
# It REFUSES rather than warns, because a warning that scrolls past still leaves a broken config
# behind: proceeding would wire seven groups into settings while the plugin supplies the same ones.
# The installer already declines to clobber a command you have edited; declining to build a knowingly
# doubled configuration is the same principle.
if [ "$PLUGINMODE" = 0 ] && [ "$HFP" = 0 ] && [ -f "$TARGET/skills/raememberit/hooks/hooks.json" ] && [ "$FORCE" != 1 ]; then
  warn "a raememberit PLUGIN is also installed at $TARGET/skills/raememberit"
  warn "It supplies these same hooks. Wiring them into settings as well makes every hook fire TWICE."
  warn ""
  warn "Pick one route:"
  warn "  ./install.sh --as-plugin      keep the plugin; it supplies the hooks (removes ours from settings)"
  warn "  rm -rf $TARGET/skills/raememberit"
  warn "                                drop the plugin, then re-run this"
  die  "refusing to create a doubled configuration. Pass --force to do it anyway."
fi
if [ "$DRY" = 1 ]; then printf '  would: merge hook wiring into %s/settings.json\n' "$TARGET"; else
python3 - "$SRC/engine/settings.fragment.json" "$TARGET/settings.json" "$MEM" "$PLUGINMODE" "$SHIM" "$HFP" <<'PY'
import json, os, sys
frag_p, set_p, mem = sys.argv[1], sys.argv[2], sys.argv[3]
plugin_mode = sys.argv[4] == "1"
shim = sys.argv[5] if len(sys.argv) > 5 else ""
hooks_from_plugin = len(sys.argv) > 6 and sys.argv[6] == "1"
# Either arrangement means a plugin supplies the hooks, so settings must carry none of ours.
plugin_owns_hooks = plugin_mode or hooks_from_plugin
# Plugin mode wires no hooks, so it must not REQUIRE the standalone wiring fragment — which the
# plugin deliberately does not ship, because a plugin user never merges it.
frag = {"hooks": {}} if plugin_owns_hooks else json.load(open(frag_p))
cur  = json.load(open(set_p)) if os.path.exists(set_p) else {}
hooks = cur.setdefault("hooks", {})
MARK = "/raememberit/engine/hooks/"

def is_ours(group):
    return any(MARK in (h.get("command") or "") for h in group.get("hooks", []))

replaced = added = kept = removed = 0

# In plugin mode the plugin's own hooks.json supplies every hook, so settings must carry NONE of ours.
# NOT adding them is not enough: a config that was installed standalone FIRST still has seven hook
# groups sitting there, and the plugin's nine arrive alongside them. Measured: everything fires twice.
# That is the exact failure this installer exists to warn about, reachable through its own flags — so
# plugin mode REMOVES raememberit's own hook groups. Anyone else's are untouched.
if plugin_owns_hooks:
    for ev in list(hooks.keys()):
        keep = [g for g in hooks[ev] if not is_ours(g)]
        removed += len(hooks[ev]) - len(keep)
        if keep:
            hooks[ev] = keep
        else:
            del hooks[ev]

for ev, groups in ([] if plugin_owns_hooks else frag["hooks"].items()):
    existing = hooks.get(ev, [])
    mine  = [g for g in existing if is_ours(g)]
    yours = [g for g in existing if not is_ours(g)]
    kept += len(yours); replaced += len(mine)
    # yours first: your hooks keep their relative order and are never dropped
    hooks[ev] = yours + groups
    added += len(groups)

# Publish the corpus path so hooks, the eval harness and the assistant's own shell all agree on
# one location without anyone having to remember a flag.
# Standalone publishes the corpus path through settings `env`. Plugin mode must NOT: an explicit
# RAEMEMBERIT_* beats a plugin option by design, so writing it here would silently make the
# manifest's own `memoryDir` option dead on arrival.
if not plugin_mode:
    env = cur.setdefault("env", {})
    env["RAEMEMBERIT_MEMORY_DIR"] = mem

# Allow the WRITE HELPER, not the Edit tool. An Edit() rule aimed inside a `.claude` path is refused
# by the sensitive-file gate no matter what it says, so the write path is a Bash script and this is
# the rule that makes it promptless.
perm  = cur.setdefault("permissions", {})
allow = perm.setdefault("allow", [])
# Plugin mode aims the rule at the version-free wrapper the SessionStart hook places; standalone aims
# it at the engine in the config dir. Either way it is one literal absolute path that never moves.
if plugin_mode:
    helper = shim
else:
    helper = os.path.join(os.path.dirname(set_p), "raememberit", "engine", "mem-write.sh")
new_rules = 0
rules = [f"Read({mem}/**)"]
if helper:
    rules = [f"Bash({helper}:*)", f"Bash(bash {helper}:*)"] + rules
for r in rules:
    if r not in allow:
        allow.append(r); new_rules += 1

json.dump(cur, open(set_p, "w"), indent=2); open(set_p, "a").write("\n")
if plugin_owns_hooks:
    if removed:
        print(f"  \033[1;32m✓\033[0m {removed} raememberit hook group(s) REMOVED from settings — the plugin\n      supplies them, and both together would fire every hook twice")
    else:
        print("  \033[1;32m✓\033[0m hooks left to the plugin — wiring them here as well would fire each one twice")
else:
    print(f"  \033[1;32m✓\033[0m {added} raememberit hook group(s) wired · "
          f"{replaced} previous raememberit group(s) replaced · {kept} of your own hook group(s) preserved")
print(f"  \033[1;32m✓\033[0m corpus path published · {new_rules} permission rule(s) added so the write\n      helper runs without prompting")
PY
fi

# ── index + verification ────────────────────────────────────────────────────────────
say "Index"
if [ "$DRY" = 1 ]; then printf '  would: rebuild the indexes and verify\n'; else
  if [ "$PLUGINMODE" = 1 ]; then ENG="$SRC/engine"; else ENG="$TARGET/raememberit/engine"; fi
  # THE REBUILD'S EXIT CODE IS A VERDICT ABOUT THE CORPUS, NOT ABOUT THIS INSTALL. It exits 1 when the
  # always-on tier is over budget — and this script runs under `set -e -o pipefail`, so piping it
  # through sed used to abort the installer right here: engine and hooks already replaced, the
  # verification below skipped, "Done" never printed, exit 1. An upgrade that reported failure because
  # the corpus it had just correctly left alone was large. Measured 2026-09-30. Capture, report, go on.
  RB_RC=0
  RB_OUT=$(CLAUDE_CONFIG_DIR="$TARGET" RAEMEMBERIT_MEMORY_DIR="$MEM" bash "$ENG/rebuild-index.sh" 2>&1) || RB_RC=$?
  printf '%s\n' "$RB_OUT" | sed 's/^/  /'
  if [ "$RB_RC" != 0 ]; then
    warn "the always-on index is over its budget (see above). The install itself is complete;"
    warn "  demote feedback memories with \`metadata.scope: domain\` when convenient. Verdict in $MEM/.index-status"
  fi
  # No installed command files to check in plugin mode — the plugin's are managed and carry no slots.
  [ "$PLUGINMODE" = 1 ] || bash "$SRC/tools/check-filled.sh" "$TARGET/commands" | sed 's/^/  ✓ /'
  CLAUDE_CONFIG_DIR="$TARGET" RAEMEMBERIT_MEMORY_DIR="$MEM" python3 "$ENG/eval/run_eval.py" --health \
    | sed -n '1p' | sed 's/^/  /'
fi

say "Done"
if [ "$GUIDED" != 1 ]; then
cat <<EOF
  Next:
    1. Paste $FRAG into your CLAUDE.md (or reference it).
    2. Memories are written by mem-write.sh over Bash, allow-listed above.
       Claude Code refuses its edit tools on paths inside a .claude directory as sensitive files,
       and no permission rule changes that — so if you ever see that refusal, the command reached
       for the wrong tool.
    3. Try it:  /learn something you just worked out   then   /recall that topic
  Re-run this installer any time; it upgrades in place and never touches your memories.
EOF
exit 0
fi

# ── guided walkthrough ─────────────────────────────────────────────────────────────────
step "One thing to add yourself"
note "I wrote an instructions fragment but did NOT touch your CLAUDE.md:"
note "  $FRAG"
note ""
note "It tells Claude the corpus exists and when to use the two commands. Without it they still"
note "work when you type them, but they will not fire on their own — which is most of the value."
if confirm "Append it to a CLAUDE.md now?"; then
  cmd_path=""
  printf '   path to your CLAUDE.md [skip]: '
  [ -r /dev/tty ] && { read -r cmd_path </dev/tty || cmd_path=""; }
  printf '\n'
  if [ -n "$cmd_path" ] && [ -f "$cmd_path" ]; then
    printf '\n' >> "$cmd_path"; cat "$FRAG" >> "$cmd_path"
    ok "appended to $cmd_path"
  else note "skipped — paste it in whenever you like"; fi
else note "not appended — the fragment is there when you want it"; fi
pause

step "Your first loop — do this now, it takes two minutes"
note "1. Start Claude, then look something up that already exists:"
note ""
note "      /recall tail exit code"
note ""
note "   You should get a rule about \`| tail && echo OK\` reporting success over a failing build."
note "   If you get \"no prior memory\", something is wrong — please say so."
note ""
note "2. Then write something of your own. Pick a real thing you worked out recently,"
note "   not a test — the point is to see whether it is worth keeping:"
note ""
note "      /learn the staging deploy needs the VPN even though the runbook omits it"
note ""
note "   Watch it search for an existing memory BEFORE writing. That step is the whole"
note "   discipline; if it writes blindly, that is a bug worth reporting."
note ""
note "3. Quit, start again, and recall that topic. Written in one session, found in the next —"
note "   that round trip is the product. Everything else is plumbing."
pause

step "What the hooks will do to your session"
note "· every new context   the always-on index is injected once, then suppressed until it resets"
note "· session start       if enough logs have piled up, a pattern sweep is OFFERED, never run"
note "· before compaction   a nudge to capture memory first"
note "· session end         both indexes regenerate from frontmatter"
note "· session end, no log today   a reminder"
note ""
if [ "$PLUGINMODE" = 1 ]; then
  note "That last one surprises people. Set the plugin's \"Require an interaction log\" option to"
  note "strict to make it BLOCK the session from ending instead, or off to silence it."
else
  note "That last one surprises people. Set RAEMEMBERIT_REQUIRE_LOG=strict in settings.json to make"
  note "it BLOCK the session from ending instead, or =off to silence it. Default is a reminder."
fi
pause

step "If you want out"
if [ "$PLUGINMODE" = 1 ]; then
  note "  claude plugin uninstall raememberit    removes the plugin: engine, hooks and commands"
  note ""
  note "Your MEMORIES are not in the plugin — they are at $MEM, and uninstalling cannot touch them."
  note "That is deliberate: a managed directory is replaced on every update, so a growing corpus"
  note "could never have lived there. Two leftovers to clear by hand if you want a clean sweep:"
  note "the permission rule in settings, and the fragment if you pasted it into your CLAUDE.md."
else
  note "  ./uninstall.sh            removes the tooling, KEEPS your memories"
  note "  ./uninstall.sh --purge    also deletes them, after making you type DELETE"
  note ""
  note "It removes only its own hooks, commands and rules. Your settings and your own hooks survive."
fi
pause

step "If something is wrong"
note "The single most useful thing you can report is the first moment you were confused —"
note "what you expected, and what happened instead. Write that down while it is fresh; it"
note "evaporates within a day."
note ""
note "Second most useful: anything irritating enough that you would turn it off. Especially"
note "the hooks — a thing that is mildly annoying every session compounds into uninstalled."
printf '\n'
ok "Set up. Go and use it."
