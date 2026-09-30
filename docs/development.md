# Development

How the project checks itself, and how to change it without breaking the checks.

## Run everything

```bash
tools/test-all.sh
```

500 assertions across ten suites, plus the plugin lifecycle cycle and the upgrade matrix outside them. CI runs the same
command on Ubuntu and on macOS's bash 3.2, and the sanitization gate is the pre-commit hook.

| Suite | Asserts |
|---|---|
| `test-sanitize-scan.sh` | the gate's own self-test: shapes, the additive private list, zero-files-is-an-error |
| `test-dedup.sh` | the duplicate-prevention loop: `find-similar.py` before the write, `--strict-dupes` after |
| `test-mem-write.sh` | the write helper enforces the schema and the tiers |
| `test-install.sh` | fresh install, re-run, dry-run, seed record, over-budget index, `--check`, engine manifest, uninstall — against a throwaway config dir |
| `test-plugin.sh` | the generated plugin matches its sources, every route, the routes cannot double, uninstall leaves no dangling hook |
| `test-tripwire.sh` | the delivery path: tiering, the always-on budget, the truncation tripwire — mutation-tested |
| `test-context.sh` | domain tags, the native silo listing, the router in every mode, the correction detector and the learn nag |
| `test-wizard.sh` | the front door: every verb, no jargon on the happy path, defaults with nobody present, the `CLAUDE.md` note round trip, from inside the plugin |
| `test-upgrade-matrix.sh` | three released versions from git history × three routes, each used like a person and then updated by this tree — runs in CI with full history; skips itself on a shallow clone |
| `test-docs.sh` | the docs describe the thing that exists: hook table generated from the wiring, assertion count measured, every internal link resolves, the frozen baseline still describes a fresh install |

Two checks compare the project against itself rather than against a number someone typed:

- **`starter/baseline.json`** freezes the retrieval score of the shipped starter corpus — literal
  8/12, expanded 12/12. That gap *is* the measured value of `/recall`'s query-expansion step, and a
  change to a starter rule's description that breaks retrieval fails the run.
- **`tools/test-docs.sh`** fails when the hook table drifts from `engine/settings.fragment.json`,
  when the assertion count in the docs stops being true, when a doc links to a page that is not
  there, or when the committed plugin manifest lags `VERSION`.

## The lifecycle cycle

`tools/test-lifecycle.sh` runs a real `claude plugin install → update → uninstall` against a
throwaway config dir and asserts the corpus comes through byte-identical, mtimes included. It needs
the `claude` CLI and installs the last **commit**, not the working tree, so it lives outside
`test-all.sh` and skips itself in CI. A skip is "not measured here", never a pass; run it by hand
after committing plugin changes.

## One source, two shapes

The plugin tree is **generated**. Edit `engine/`, `protocol/`, `starter/`, `scaffold/` or the
front door, then:

```bash
tools/build-plugin.sh          # regenerates plugin/ in full
tools/gen-hook-table.sh        # the hook table for docs/commands.md
```

`test-plugin.sh` rebuilds into a temp dir and diffs against the committed tree, so editing either
side without rebuilding fails. `VERSION` at the root is the one version; a test fails if any
generator restates it as a literal.

## The sanitization gate

`tools/sanitize-scan.sh` refuses identifying and secret-shaped content before it reaches a public
repo. It is additive and split on purpose: `tools/denylist.example.txt` carries universal secret
shapes and is always loaded; private vocabulary lives in `.denylist.local.txt` (gitignored) and
extends the shapes rather than replacing them — a denylist of an organisation's internal terms,
committed, is itself the disclosure it exists to prevent.

```bash
tools/test-sanitize-scan.sh    # its self-test, first
tools/install-hooks.sh         # wire it as pre-commit
tools/sanitize-scan.sh         # scan the tree
```

Scanning zero files is an error, not a pass, and there are no file exclusions: an excluded file is
a blind spot. A line may carry `sanitize-allow` to exempt itself, visibly.

## Testing in isolation

`CLAUDE_CONFIG_DIR` relocates a session's entire config; every suite installs into a throwaway
directory and fingerprints the real corpus around itself. Two traps, both measured:

- an ambient `RAEMEMBERIT_MEMORY_DIR` from your real `settings.json` outranks `CLAUDE_CONFIG_DIR`
  inside hooks and scripts — every suite unsets it as its first act, and the installer ignores it
  when `--config-dir` is explicit
- a sandbox isolates writes, not reads; a session there can still read the live config by absolute
  path

A test that reads the thing it is isolating from has proven nothing.

## Conventions

- bash 3.2: no `mapfile`, no associative arrays, no `${x^^}`
- a fix lands with its failing test first; counts in prose are generated or verified, never typed
- commit messages say what was wrong and how it was measured; `CHANGELOG.md` groups by what
  changed for someone using the kit
- shipped files carry no person's name: `{{USER}}` renders into commands at install time; hook
  comments say "the user"
