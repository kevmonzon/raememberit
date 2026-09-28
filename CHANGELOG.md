# Changelog

Entries are grouped by what changed for someone *using* the kit, not by commit. The reasoning
behind each change lives in the commit that made it — `git log` is the long form, this is the index.

Versions before `0.4.0` predate this file; their history is in `git log` and is not reconstructed
here, because a changelog written after the fact from subject lines is a guess wearing a date.

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
