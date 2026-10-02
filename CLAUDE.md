# raememberit — guidance for Claude Code sessions in this repo

## What this is

A memory kit for Claude Code: plain-markdown memories under `<config>/memory`, hooks that inject,
nudge and rebuild, five slash commands, and one front door (`./raememberit`). No daemon, no
database. Extracted from one engineer's daily setup and generalized; used live by the maintainer
every day, so the person running you may be its author. The manual is `docs/` — read
`docs/README.md` first, then the page that matches the task. Do not restate the manual here.

Version is the one line in `VERSION`. Status: alpha, 0.6.x.

## Map

| Path | What it is |
|---|---|
| `raememberit` | the front door: `install`, `update`, `status`, `uninstall`. Plain words, preview → confirm → summary |
| `install.sh`, `uninstall.sh` | the three install routes and every flag (`docs/advanced.md`). The front door drives these |
| `engine/` | hooks, `mem-write.sh`, `rebuild-index.sh`, the router, the eval harness. This is what gets installed |
| `protocol/` | the five command templates (`*.md.tmpl`), rendered with `{{USER}}` at install |
| `starter/`, `scaffold/` | the seed corpus, the instructions fragment, the frozen retrieval baseline |
| `plugin/` | **generated** by `tools/build-plugin.sh`. Never edit by hand |
| `tools/` | the test suites, the sanitization gate, the generators |
| `docs/` | the manual. Tested by `tools/test-docs.sh` |
| `.claude-plugin/marketplace.json` | test scaffolding for `tools/test-lifecycle.sh` only. Not a distribution channel |

## Invariants — a change that breaks one is wrong, however green it looks

- **bash 3.2.** macOS ships it. No `mapfile`, no associative arrays, no `${x^^}`. CI has a macOS job for this reason.
- **`plugin/` is generated.** Edit `engine/`, `protocol/`, `starter/`, `scaffold/` or the front door, then run `tools/build-plugin.sh`. `test-plugin.sh` diffs the committed tree against a fresh build.
- **One version.** `VERSION` at the root. A generator that restates it as a literal fails a test.
- **A fix lands with its failing test first.** Counts in prose are generated or measured, never typed. `README.md` and `docs/development.md` carry an assertion count that `test-docs.sh` verifies.
- **No person's name in shipped files.** `{{USER}}` renders at install time; hook comments say "the user". The pre-commit sanitize gate (`tools/sanitize-scan.sh --staged`) has no file exclusions and a private vocabulary list in `.denylist.local.txt` (gitignored). This file is scanned too.
- **An update never touches the corpus.** `test-lifecycle.sh` and `test-upgrade-matrix.sh` exist to prove it. Do not add a code path that writes into `<config>/memory` during install or update, except the seed step on a fresh corpus.
- **The always-on tier has a byte budget.** Anything that adds to `MEMORY.md` output must respect `RAEMEMBERIT_BUDGET` and the tripwire.
- **The router ships in shadow mode.** Do not flip the default to `inject`; the person flips it after measuring precision on their own corpus.

## Testing

```bash
tools/test-all.sh            # every suite, ~500 assertions
tools/test-lifecycle.sh      # real claude plugin install→update→uninstall; needs the claude CLI; tests the LAST COMMIT, not the tree
tools/test-upgrade-matrix.sh # three old versions × three routes; needs full git history
```

Running any suite from inside a Claude Code session on the maintainer's machine has two traps,
both measured (`docs/development.md`, "Testing in isolation"):

1. `RAEMEMBERIT_MEMORY_DIR` is exported in the live session and **outranks** `CLAUDE_CONFIG_DIR`. Set both to the sandbox, or the run rebuilds the real corpus.
2. An **empty** sandbox makes assertions silently not run and reports two failures that are rig artifacts. Seed it with a real corpus and the installed engine, then compare assertion **totals** across runs before believing any named failure.

A skip in `test-lifecycle.sh` is "not measured here", never a pass.

## The live install on the maintainer's machine

The maintainer's own Claude Code config runs this kit. When a session here touches it:

- The installed artifact is `<config>/raememberit/` (engine + fragment + `.config`). It is **not** a checkout. The source is this repo.
- Hooks arrive **only** from the plugin at `<config>/skills/raememberit/` (`raememberit@skills-dir`). The config `settings.json` carries no hook entries. If memory "stops working", run `claude plugin list` before reading any script.
- The five commands in `<config>/commands/` are the person's own, hand-edited, and the installer skips them on update. Their prose therefore rots; `tools/diff-commands.sh` (read-only) is the only thing that surfaces it.
- **The maintenance line is `./raememberit update`**, with `./raememberit status` first. Never `./install.sh --as-plugin` on this machine (it moves the engine out from under the command references) and never plain `./install.sh` (it refuses, correctly, because a plugin supplies the hooks).
- The installer's CLAUDE.md note goes between `<!-- raememberit:begin -->` / `<!-- raememberit:end -->` markers in `<config>/CLAUDE.md`. It has nothing to do with this file.

## Decisions already made — do not re-propose

| Proposal | Answer |
|---|---|
| distribute via a plugin marketplace | No. Distribution is the install script. `marketplace.json` stays only so the lifecycle test has something to install from |
| configuration profiles / bundles | No. Configuration is values, not bundles. The mechanism was built, measured unused, and removed |
| a pilot or trial phase | No. This is used live |
| make `<config>` a git repo | No. Explicitly not the intention |
| ship the persona in the public core | No. It is an optional file, the person's own |
| re-add a starter rule the person deleted | No. `.seeded-starters` exists so `--force` can tell deleted from never-seeded. If the content is wanted, the person writes it deliberately |

## How to work here

- **Preview before you write.** Show the exact diff of any change to a shipped file, the docs, or the person's config before applying it. The front door models this: preview, confirm, summary.
- **Commit messages say what was wrong and how it was measured.** `CHANGELOG.md` is grouped by what changed for someone *using* the kit, one entry per user-visible change, written when the version is cut. Read the last three entries before writing one.
- **No network from a session by default.** No `git push`, no `gh`, no `curl`. If the person asks for a push, that is a one-time authorization for that push, not a standing one.
- **Never commit without an explicit yes.** Stage files by name.
- **Proposed is not agreed.** When the person picks an option, docs and changelog say "chosen" or "proposed", never "agreed" or "signed off".
- **Dated scratch files** (`YYYY-MM-DD-*.md`, build dirs) at the repo root are working artifacts, untracked on purpose. Do not commit, move or delete them without asking.
- **When a negative result comes from a test rig, validate the rig first.** This project has been bitten by `grep -q` under `pipefail`, `| tail` masking exit codes, `--`-prefixed strings parsed as options, and empty sandboxes. The history in `git log` names each one.
