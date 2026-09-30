# Changelog

Entries are grouped by what changed for someone *using* the kit, not by commit. The reasoning
behind each change lives in the commit that made it — `git log` is the long form, this is the index.

Versions before `0.4.0` predate this file; their history is in `git log` and is not reconstructed
here, because a changelog written after the fact from subject lines is a guess wearing a date.

## Unreleased

### `/learn`'s trigger is a process now

`correction-nudge.sh` (`UserPromptSubmit`) matches a few strong correction shapes — a leading
*"No,"*, *"I told you"*, *"you should have"* — logs the hit to `memory/.corrections-log` and, in
`nudge` mode, adds one line of context naming `/learn`, at most once per ten minutes. `learn-nag.sh`
(`Stop`) notices a session with two or more corrections and no `feedback/` memory newer than the
first, and says so once; `strict` blocks the stop. `/skill-mine` now reads the corrections log for
friction, ranking a correction that recurs with nothing written down above everything else, and
`/memory-audit` reports the same gap. Knob: `RAEMEMBERIT_CORRECTIONS`.

### Retrieval no longer depends on remembering to retrieve

A new `UserPromptSubmit` hook, `context-router.sh`, scores every prompt — its tokens, the working
directory's name, any ticket key — against the catalog, the domain index, and the `description:` of
every installed command and skill, and surfaces the best few of each. No model call. **Both halves
default to `shadow`**: they log what they would have surfaced to `memory/.recall-log` and
`memory/.skill-log` and inject nothing, so precision can be measured before a single byte is added
to a prompt. `/recall` now writes the same log, and `/memory-audit` gained a retrieval-usage stage
that reads it: an archive shortlist of memories nobody has retrieved, and the precision sample that
justifies flipping the router to `inject`. Knobs: `RAEMEMBERIT_AUTORECALL`, `RAEMEMBERIT_SKILLROUTER`,
`RAEMEMBERIT_AUTORECALL_BUDGET`, `RAEMEMBERIT_ROUTER_MAX`.

### Memories can name their domain, and the second silo is in the catalog

`metadata.domain:` — a repo, tool or ticket prefix, kebab-case, comma-separated — is accepted on
any memory and enforced on write. The catalog line shows it, and `rebuild-index.sh` writes a third
derived file, `memory/.domain-index`, one row per (domain, memory), for the prompt-time hook that
follows. Claude Code's own per-project auto-memory is now listed in the on-demand catalog under its
own heading, read-only and never scored, so one grep covers both silos.

### Smaller things found by the same audit

- **`--hooks-from-plugin` is now the recommended route.** It is the one the kit's author runs, the
  only one exercised daily, and the one with the fewest moving parts on upgrade. The other two stay
  supported and tested.
- **`uninstall.sh` stripped any permission rule containing `/memory/**`**, which is a shape, not an
  identity — a user's own rule on some other memory directory would have gone with it. It now removes
  only rules naming raememberit and the one `Read()` rule aimed at this corpus.
- **`--dry-run` on the plugin routes claimed it would "merge hook wiring"** while the real run removes
  raememberit's hook groups from settings and leaves the hooks to the plugin. It now says what it does.

### A local patch to the installed engine vanished silently on upgrade

Documented as "a knob, not an edit", and it still happened: the truncation tripwire lived as a
local patch to the installed engine for a day before it was upstreamed, and one re-run in that
window would have deleted it without a word. The install now records a manifest of the engine it
wrote; an upgrade names every file that differs from it and keeps the whole previous engine at
`raememberit/engine.prev` with a runnable `diff -r`. A clean upgrade removes that directory. An
install with no record yet — anything before this version — keeps its engine once regardless.

### Nothing recorded which version was installed, so nothing could say whether to upgrade

The engine carried no marker, the hooks-only plugin reported whatever `VERSION` said when it was
generated, and the commands are frozen by design. `install.sh` now records `version=` and
`schema=` in `raememberit/.config`, and **`--check`** is a read-only comparison of an install
against the checkout: route, versions, every engine file that differs, whether the generated hook
wiring would change, and each command's drift from its template — exiting 1 with the exact re-run
when an upgrade is available. The schema number is the corpus's on-disk conventions; there is a
migrations step that has nothing to do yet and refuses a corpus newer than the installer.

### An over-budget index made an upgrade report failure

`rebuild-index.sh` exits 1 when the always-on tier is over budget — a verdict about the corpus.
The installer runs under `set -e -o pipefail` and piped that exit through `sed`, so the run
aborted at the Index step with the engine and hooks already replaced, verification skipped and
no "Done": an upgrade that reported failure because the corpus it had correctly left alone was
large. The verdict is now captured and reported, and the install completes and exits 0.

### Uninstall left the plugin's hooks firing at a removed engine

On both plugin routes the hooks live in `skills/raememberit/` and nowhere in `settings.json`.
`uninstall.sh` stripped settings and removed the engine — and left that directory behind, so
nine hooks kept firing every session at a path that no longer existed. It now removes the
directory when its manifest says it is raememberit's, strips every `RAEMEMBERIT_*` env entry
rather than only the corpus path, and the suite asserts that after an uninstall on any route no
surviving hook points at a missing file.

### A deleted starter rule came back on the next `--force`

Topping up a scaffold copied in every shipped starter that was absent, which cannot tell "never
seeded" from "deleted on purpose". The corpus now records which starters it received
(`memory/.seeded-starters`); a name in the record is a decision already taken, and only a starter
that shipped later is added. A corpus with no record — one seeded by an earlier version — gets
nothing added, a record written, and a line naming the `cp` for anyone who wants one.

### The plugin route could not be upgraded by re-running the installer

`--as-plugin` refused to touch an existing `skills/raememberit/` without `--force` — right for
a directory someone edited, wrong for everyone else, because "re-run to upgrade" silently stopped
being true on that route. A marker planted in the placed engine survived the documented upgrade.
And `--force`, the only way past it, also tops up the corpus scaffold, so upgrading the plugin
re-seeded starter rules into a corpus that had deliberately deleted them (the 2026-09-28 accident,
reproduced on demand).

The directory now carries a record of what was placed, and a re-run applies the same four-state
policy the commands have: untouched, update; edited, skip and say so. **`--replace-plugin`** is the
new, separate override. `--force` no longer replaces the plugin directory. A directory placed by an
earlier version is recorded on sight if it still matches the source; one that differs needs
`--replace-plugin` once, after which upgrades flow.

### The `SessionEnd` index rebuild was cancelled on every exit

`rebuild-index-hook.sh` ran the rebuild in the foreground. On exit the harness gives
`SessionEnd` hooks a short budget of its own, and the `timeout` in the wiring does not
extend it. A real corpus took ~1.7s to rebuild, so every exit printed
`SessionEnd hook [...rebuild-index-hook.sh] failed: Hook cancelled`, and the index never
refreshed at exit. Nothing was corrupted: the rebuild stages to temps and `mv`s them in,
so a killed run leaves the previous index intact. It was simply stale.

The rebuild is now detached (`set -m`, `nohup`, every fd released). The hook returns in
milliseconds and the rebuild finishes after the session is gone. The wired timeout drops
from 30s to 5s, in line with the other hooks, because the hook no longer does the work.

## 0.5.2

Fixes a warning `0.5.1` introduced, which fired on the setup this installer exists
to serve.

The unpasted-fragment check grepped for `raememberit` — the kit's own name — so it
warned at every adopted install: someone who read the fragment and then wrote the
instructions in their own words, naming `/learn` and `/recall` and their corpus
rather than the tool. Their memory system works, and the installer told them it did
not. Caught on the first real install after shipping it.

Same defect as the rest of `0.5.x`: the check measured a proxy (is the tool named)
rather than the property (does anything tell Claude a corpus exists). It now matches
the corpus path, `/learn`, `/recall`, a Memory heading, or the name.

Four shapes covered, because the failure has two directions: no `CLAUDE.md` warns;
a `CLAUDE.md` about tabs and make **still** warns, so the check has not degraded
into "is there a file"; own-words instructions are quiet; a pasted fragment is quiet.

A warning that cries wolf on the recommended configuration is worse than no warning
— it trains the reader to skip it, which is how nine false claims in the adopted
commands survived as long as they did.

275 assertions across seven suites, plus the lifecycle cycle outside them.

## 0.5.1

One bug fix on a destructive path, and one guard against this kit's own
characteristic failure. Both found by running the installer and uninstaller as a
newcomer would, rather than reading them.

### `uninstall.sh` never got the precedence fix the installer did

`0.4.0` taught `install.sh` that a flag the caller typed beats a variable the
environment happened to carry, after an ambient `RAEMEMBERIT_MEMORY_DIR` redirected
a `--config-dir` install onto a live corpus. `uninstall.sh` resolved the corpus the
old way, and nobody noticed — because uninstall only *reports* the corpus by
default, so the wrong path was printed rather than acted on.

Uninstalling a throwaway target reported `KEPT: 650 file(s)` at a real corpus while
the target held 15. Nothing was damaged. But `--purge` deletes whatever that
variable resolves to, so an ambient value could offer to erase a corpus the caller
never named. The typed `DELETE` confirmation names the path, which protects
someone who reads it and nobody who is following instructions.

### The installer could report success and do nothing

Pasting `INSTRUCTIONS-fragment.md` into a `CLAUDE.md` is manual on purpose — this
installer does not edit anyone's `CLAUDE.md`. Skip it and every hook still fires,
the corpus is still written, the indexes still rebuild, and nothing ever tells
Claude the corpus exists: seven green steps and a no-op, which is precisely the
failure this kit was built to detect elsewhere.

It now looks for a `CLAUDE.md` that references it and says when it finds none,
naming the paths it checked. Looked for, never enforced — a false "not referenced"
is noise, a missed paste is silence.

### Tests

Nine assertions, both fixes mutation-proven by reverting them. The precedence test
uses a **decoy** corpus and asserts it is untouched after both install and
uninstall, so the suite proves this without going near a real one.

273 assertions across seven suites, plus the lifecycle cycle outside them.

## 0.5.0

Eight commits, and seven of them are the same defect at different layers: something that
reported success while doing nothing. None of them errored. All of them passed.

### `archive/` became a real tier

Nothing read it — not `rebuild-index.sh`, not the catalog, not `/recall`. Memories moved there were
unreachable by every documented retrieval path, which makes "archive" a quiet delete rather than a
filing. It is now listed in `MEMORY-CATALOG.md` under its own heading: findable, visibly finished,
and costing the always-on tier nothing.

It stays out of the eval's **scored** corpus deliberately — finished work should not be marked for
retrieval quality — but archived names are valid **link targets**, because *not scored* and *not a
valid target* are different claims. Conflating them turned working `[[links]]` into reported
danglings the moment anything was archived.

**Ordering matters:** install before moving anything to `archive/`. The `SessionEnd` hook runs the
*installed* `rebuild-index.sh`, so an older copy un-indexes the directory on the next session end.

### Instruments that were lying

- **The audit's hook check** named `settings.json`, which two of the three install routes leave
  empty by design. An audit following it concluded the memory system was unwired — a confident false
  negative, produced by the check written to prevent confident false negatives.
- **The eval undercounted the native silo**, keying a dict by filename stem so four stores each
  holding a `MEMORY.md` collapsed into one: 17 files reported as 14. A dict keyed on a non-unique
  field does not error; it drops, and prints the smaller number as fact.
- **The staleness check counted ordinary English.** A case-insensitive body scan for SHIPPED /
  DONE / merged / closed matched *"assumes Phases 0–3 done"* and *"PR closed unmerged"*, reporting
  40 of 65 project memories as finished where the number worth acting on was 3 — and recommending a
  sweep that would have buried twelve in-flight tickets.
- **The version was two literals.** `build-plugin.sh` wrote the marketplace tree's manifest and
  `gen-hooks-only-plugin.py` wrote the one installs actually generate. A bump to the first never
  reached a real install, and nothing compared them. There is now a `VERSION` file, and an assertion
  that no generator restates it.

### Documentation that described the previous architecture

`metadata.scope` shipped in the write path and the audit while three documents went on stating the
model it replaced — including `INSTRUCTIONS-fragment.md`, the file every install pastes into a
`CLAUDE.md`. Corrected, along with `/recall`'s description of the tiers and the quickstart's week-one
habits, which are two habits and one judgement call.

### Tests

- **`--dry-run` had no coverage**, despite being the first command a cautious adopter runs. Nine
  assertions now: on a fresh target it must leave the directory completely empty; against an existing
  install every file is fingerprinted before and after and required identical.
- The README's strongest claim — that an update does not disturb a corpus — now carries its
  provenance. Those nineteen lifecycle assertions need the `claude` CLI, so they run on a developer
  machine and **never in CI**. A green badge says nothing about them either way.

264 assertions across seven suites, plus the lifecycle cycle outside them.

## 0.4.0

### The always-on index can now fail to be delivered, and says so

Past an undocumented size ceiling the harness does not inject a hook's `additionalContext`. It
writes the payload to `projects/<proj>/<session>/tool-results/hook-*-additionalContext.txt`, hands
the model a short preview and that path, and returns no error — the hook still exits 0. Measured on
a real corpus: **13 consecutive sessions delivered 8 of 71 index entries** with nothing anywhere
reporting it.

- **New `SessionStart` hook, `truncation-tripwire.sh`.** Detects this from the artifacts the harness
  itself writes, not from a size guess — the ceiling is undocumented, was only ever observed from
  below, and lives in a self-updating binary. Its window is also its reset, and its advice tracks
  the last rebuild verdict rather than the artifact count, so a trimmed index is told the warning is
  historical instead of being told to trim again.
  Knobs: `RAEMEMBERIT_TRIPWIRE`, `RAEMEMBERIT_TRIPWIRE_WINDOW_H`.
- **Feedback memories can declare a tier.** `metadata.scope: global | domain` keeps standing rules
  always-on and demotes the rest to `MEMORY-CATALOG.md`, where `/recall` still finds them. **An
  absent `scope` means `global`**, deliberately: defaulting the other way would empty the always-on
  tier the first time an older corpus is rebuilt.
- **`rebuild-index.sh` renders to a temp file and `mv`s it.** `{ ... } > MEMORY.md` truncates at
  open, so any mid-stream failure previously left a half-written index. It also enforces a byte
  budget (`RAEMEMBERIT_ALWAYS_ON_BUDGET`, default 12000), recording `OK`/`OVER` in
  `<corpus>/.index-status`. The index is installed either way — stale or missing is worse than large.
- **`rebuild-index-hook.sh` logs instead of discarding.** Its output now lands in
  `<corpus>/.index-rebuild.log` rather than `/dev/null`.
- **`/learn` teaches the tier choice**, so a trimmed tier does not silently refill.
- **The eval asserts delivery, not only retrieval.** `run_eval.py` reads the corpus off disk, so it
  stayed green through every truncated session; it now reports the delivery verdict above the
  scores, and the frozen starter baseline holds a fresh install to it.
- **New suite `tools/test-tripwire.sh`** — 25 mutation-tested assertions covering the whole delivery
  path.

### Install routes

- `./install.sh --as-plugin` places `plugin/` at `<config>/skills/raememberit/`, which auto-loads
  with no settings entry, and the two routes can no longer double every hook.
- `./install.sh --hooks-from-plugin`: the engine stays at `<config>/raememberit/engine/` and only the
  hooks come from a plugin — the arrangement an adopted setup actually ends up in.
- `--as-plugin` now verifies the write helper exists before naming it in a permission rule, instead
  of computing the path it *would* have used and reporting that as fact.
- **An explicitly passed `--config-dir` outranks an ambient `RAEMEMBERIT_MEMORY_DIR`.** Publishing
  that variable into a real settings file had made every `--config-dir /tmp/sandbox` run operate on
  the live corpus while believing it was isolated. `tools/test-plugin.sh` now unsets every
  `RAEMEMBERIT_*` variable as its first act.
- An update does not disturb a corpus — asserted by `tools/test-lifecycle.sh` running a real
  install → update → uninstall cycle, mtimes included.

### Documentation

- README documents every user-facing variable; the three that are really install flags or plugin
  options (`--user`, `--persona`, `--vocabulary`) are named as configuration rather than knobs.
- `docs/LIFECYCLE.md` covers the new hook and the two files it reads.
- The `/memory-audit` protocol gained a delivery stage, checked *before* any retrieval number.
