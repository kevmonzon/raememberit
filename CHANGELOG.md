# Changelog

Entries are grouped by what changed for someone *using* the kit, not by commit. The reasoning
behind each change lives in the commit that made it — `git log` is the long form, this is the index.

Versions before `0.4.0` predate this file; their history is in `git log` and is not reconstructed
here, because a changelog written after the fact from subject lines is a guess wearing a date.

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
