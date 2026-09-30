# Upgrading and uninstalling

Re-running is always safe. This page is what "safe" means, exactly, and what to do when it is not
enough.

## Check, then update

```bash
git pull
./raememberit status       # read-only: installed version, this download's version, anything wrong
./raememberit update       # what will change, then the update, then what changed
```

`status` exits 1 and names the command when an update is available; `update` says nothing to do
when there is not.

## What an update touches, and what it never does

| | On update |
|---|---|
| your memory folder | **never touched** — asserted by fingerprint, mtimes included, on every route |
| a command you edited | left alone and named; the shipped version is saved beside it with a runnable `diff` |
| a command you never touched | updated |
| the background tools | replaced; anything you changed in them is named and kept at `raememberit/engine.prev` with a `diff -r` |
| the background reminders | regenerated from this version's wiring; new ones are quiet by default |
| your settings, your own hooks, your permission rules | untouched — only raememberit's own entries are rewritten |
| `CLAUDE.md` | untouched if it already speaks of memories; the four-line note is offered if not |
| starter rules you deleted | stay deleted — the corpus records which ones it received |
| the corpus schema | recorded in `raememberit/.config`; a corpus newer than the installer is refused, not guessed at |
| the install route | kept: an `--as-plugin` install stays one, a `--hooks-from-plugin` install stays one. A standalone install (hooks in `settings.json`) is moved to the recommended arrangement, and the preview says so before asking |

Every released version since 0.4.0, on every route, is updated by this tree's front door in CI:
sixteen assertions per cell, including that the person's memories, edited command, deleted
starter, own hook and non-ASCII setting all survive, and that a second update is a no-op.

An update that finds the always-on tier over budget says so and completes anyway; the verdict is a
fact about your corpus, not a failure of the update.

## Edited commands drift on purpose

The five memory commands are yours after install, so an update cannot bring them new mechanics
without overwriting your text. The cost is silent unless you look:

```bash
./raememberit status --commands           # +/- lines against the shipped template, per command
diff <config>/raememberit/shipped/learn.md <config>/commands/learn.md
```

Port what you want by hand, or take the shipped versions with `./raememberit update --advanced --force-commands`.

## `engine.prev`

Present only when the last update found local changes in the tools. A clean update removes it, so
its presence means exactly one thing. Re-apply what you need, or better, open an issue so it ships.

## Uninstall

```bash
./raememberit uninstall                     # removes the tools, KEEPS your memories
./raememberit uninstall --and-my-memories   # also deletes them, after you type "delete my memories"
```

Removed: the tools, the reminders, the plugin directory it placed (checked by manifest name), its
permission rules and `env` entries, its commands, and the marked note in `CLAUDE.md`. Kept: your
memories, your settings, your own hooks, a `CLAUDE.md` you wrote yourself. Asserted, not promised —
including that after uninstall no surviving hook points at a file that is gone.

Memories are plain markdown and stay readable with this tool gone.

## The plugin route

If you installed as a plugin from a marketplace, `claude plugin update` is the update and
`claude plugin uninstall raememberit` is the uninstall; the corpus lives outside the plugin and comes
through both byte-identical. `/raememberit:setup` re-run adds the permission rule after the first
restart. Details in [Advanced](advanced.md).
