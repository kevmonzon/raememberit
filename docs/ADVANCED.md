# Advanced: every route, every flag

`./raememberit install` is the front door and chooses the recommended arrangement for you. This is
the reference for what sits behind it — `install.sh` and `uninstall.sh`, which do the work and know
every option. Reach them through the front door with `--advanced`:

```bash
./raememberit install --advanced --help               # install.sh's own help
./raememberit install --advanced --dry-run            # any install.sh flags, unchanged
./raememberit uninstall --advanced --purge
```

or call the scripts directly; the front door adds nothing they cannot do.

## Two routes, one implementation

| | For | Where the engine lives | Where the hooks come from |
|---|---|---|---|
| **`./install.sh --hooks-from-plugin`** — *recommended* | any setup, customized or not | `<config>/raememberit/engine/` | a small generated plugin |
| `./install.sh --as-plugin` | starting fresh, nothing to preserve | inside the plugin | the plugin |
| `./install.sh` | a setup that wants its hook entries visible in `settings.json` | `<config>/raememberit/engine/` | `settings.json` |

**The first row is the recommended one.** It is the arrangement the kit's own author runs, the only one
exercised daily, and the one whose upgrade path has the fewest moving parts: the engine never moves, so
every command reference stays valid; the hooks live in a generated plugin, so `settings.json` carries
none of them and nothing can double; and an upgrade regenerates that plugin from the fragment rather
than replacing a directory you might have touched. The other two work and are tested, but each adds an
update path to keep safe, and three of those is how the defects fixed in `0.6.0` went unnoticed.

The first row is not a variant for its own sake. **Hand-edited commands hardcode the config-dir engine
paths**, so any route that moves the engine breaks them *silently* — they grep nothing and report a
confident absence. That mode keeps the engine still while moving only the hooks, and the plugin it
generates needs no path rewriting at all: the settings fragment's commands already point exactly where
that mode leaves the engine, so they are copied verbatim. Nothing is transformed, so nothing can be
transformed wrongly.

Both routes are **this script**. There is a `marketplace.json` as well, but it exists so
`tools/test-lifecycle.sh` can run a real install/update/uninstall cycle — the only way to prove an update
leaves a corpus alone. Distribution is the script.

**The two routes cannot be combined, and the installer enforces that.** Standalone wires seven hook
groups into `settings.json`; the plugin supplies the same ones. Running both fires every hook twice — no
error, just doubling. So `--as-plugin` **removes** raememberit's own hook groups from settings (yours are
untouched), and a standalone install onto a config that already has the plugin **refuses**, naming both
ways out. `--force` overrides it for someone who means it.

They serve genuinely different cases. A plugin's commands are managed files replaced on every update,
so it cannot carry commands whose text is *yours* — which is exactly the case this kit's own author
turned out to be.

**The plugin.** Copy `plugin/` to `<config>/skills/raememberit/` and it auto-loads as
`raememberit@skills-dir` with **no settings entry at all** — no marketplace, no `pluginDirs`, no
`enabledPlugins`. Then run **`/raememberit:setup`**, which is the installer: it reports what it found,
names any memory hooks you already have rather than doubling them, shows the one permission rule before
adding it, seeds the corpus, offers the instruction fragment, and walks the first loop on something real.

**The whole `plugin/` tree is generated** by `tools/build-plugin.sh` from `engine/`, the protocol
templates and `engine/settings.fragment.json`; `tools/test-plugin.sh` rebuilds it into a temp directory
and diffs, so editing either side without rebuilding fails. Two descriptions of one mechanism is a drift
surface and this project has been bitten by it three times.

**Adopted commands are never overwritten — and `tools/diff-commands.sh` keeps that revisitable.** The
installer refuses to touch a command it did not write, because in an adopted setup the text is *yours*.
The cost is silent: improvements to command mechanics never arrive and nothing says so. That script
renders each template exactly as the installer would — using the remembered addressee, so nothing looks
changed merely because a flag was omitted — and diffs it against what is installed. It is strictly
read-only, and an assertion requires the command files to be byte-identical after two runs.

**Does an update disturb a corpus?** No — measured, not argued. `tools/test-lifecycle.sh` runs the
real `install → update → uninstall` cycle against a throwaway config directory and asserts the corpus
is byte-identical afterwards, mtimes included, and that memories survive an uninstall. Nineteen
assertions. It lives outside `test-all.sh` because a directory-marketplace install clones the **git**
state, so it tests the last commit rather than the working tree.

**Read that claim with its provenance, because it is the one CI does not check.** Those nineteen
assertions need the `claude` CLI, which a bare runner does not have. The Ubuntu job invokes the suite
and it skips itself; the macOS job runs `test-all.sh`, which excludes it by design. So the cycle is
measured on a developer machine, by hand, and a green CI badge says nothing about it either way — a
skip is "not measured here", never a pass. Every other number in this section is verified on every
push; this one is verified when someone runs it.

**The one thing a plugin cannot declare** is a permission rule, and its own install path carries a
version, so a rule aimed there would die on every update. A `SessionStart` hook places a *wrapper* at
the version-free `$CLAUDE_PLUGIN_DATA/bin/`, and the rule names that. A copy would not work: every
engine script finds its siblings with `$(dirname "$0")`.

What a plugin still **cannot** supply: permission rules and settings `env`. So the `Bash(...)` allow
rule for the write helper, and the knobs, stay in the user's own settings — one entry each, added once.

**Or merged into your settings** by `install.sh`, which is the path for anyone whose commands are
their own.

## `install.sh` and its flags

```bash
./install.sh                                          # into ${CLAUDE_CONFIG_DIR:-~/.claude}
./install.sh --user Alex --persona ~/my-voice.md      # optional
./install.sh --dry-run                                # say what would change, change nothing
./install.sh --check                                  # read-only: installed vs this checkout
```

`--check` answers "is my install current?" — which had no answer before, because nothing recorded
the installed version and the commands are frozen by design. It reports the route it detects, the
installed and checkout versions, every engine file that differs, whether the generated hook wiring
would change, and how far each installed command has drifted from its template. It exits 1 with the
exact re-run for that route when an upgrade is available. The install records `version=` and
`schema=` in `raememberit/.config`; the schema number names the on-disk conventions a corpus relies
on and is what a future migration acts on, instead of guessing from file shapes.

Configuration is **values, not bundles**: `--user`, and optionally `--persona FILE` and
`--vocabulary FILE`. Everything else is an environment knob in `settings.json` (see below). There was
once a "profile" mechanism here — named bundles carrying all four — which was built, documented,
tested and used by nobody, because one person's configuration is a handful of values.

A fresh interactive install runs **guided**: it surveys what it found, warns if you already have
memory hooks of your own (adopting alongside them doubles the work, and the installer will not remove
them for you), shows what it is about to change, walks you through the first `recall` → `learn` → recall
round trip, explains what each hook does to your session, and tells you how to uninstall before you
need to. `--no-guided` skips it; a re-run is terse by default.

Idempotent: re-run it to upgrade. It **merges** hooks into an existing settings file rather than
replacing it, never overwrites an existing corpus, and never touches credentials. A `--force` top-up
adds only starter rules that shipped *after* the corpus was seeded — the corpus records which ones it
received in `memory/.seeded-starters`, so a rule you deleted stays deleted. A corpus from before that
record gets nothing added and a line saying how to copy one in by hand.

### Adopting this into a setup you have already customized

A re-install never overwrites a command you have edited. The installer keeps a manifest of what it
wrote (`raememberit/.installed-commands`) and treats each command one of four ways:

| State | Action |
|---|---|
| absent | install |
| identical to what we would write | already current |
| matches the manifest — ours, untouched | update |
| differs from the manifest, or has no entry at all | **skip**, and say so |

A skipped command's shipped version is saved to `raememberit/shipped/<name>` and the installer prints
a runnable `diff`, so the warning can be acted on rather than merely noted. `--force-commands` takes
the shipped versions anyway; it is deliberately **separate** from `--force`, because topping up a
scaffold should never be a reason to discard someone's command text.

**The plugin directory follows the same policy.** `--as-plugin` records a fingerprint of what it
placed (`skills/raememberit/.raememberit-placed`), so a re-run upgrades a directory you never touched
and skips one you edited, saying so. `--replace-plugin` takes the shipped tree anyway, and is separate
from `--force` for the same reason: the one flag that used to do both re-seeded starter rules into a
corpus that had deliberately deleted them. A directory placed before the record existed is recorded on
sight if it is still byte-identical to the source; if it differs, it is treated as unknown provenance
and needs `--replace-plugin` once.

Without the manifest the only safe policy would be "never update", stranding everyone on whatever
version they first installed. With it, upgrades reach untouched files and stop at edited ones — the
same reason a package manager treats config files this way.

