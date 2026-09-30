# Adopting raememberit

The honest version: what it is, what is known to be rough, and how to back out.

## What it is, in three sentences

It is a memory discipline for Claude Code: a small set of commands and hooks that make capturing a
fact cheap and looking one up reflexive. Everything it stores is plain markdown in a folder you own —
no database, no service, nothing leaves your machine. It grew out of one person's setup and has been
generalized so it can be someone else's.

## What the installer does for you

```bash
./raememberit install
```

You do not need to read anything first. It tells you what it found, asks what Claude should call
you, shows each change before making it — including the short note it offers to put in your
`CLAUDE.md` — and ends with a two-minute round trip to try. `./raememberit status` afterwards says
whether anything is wrong, in plain words.

Fifteen minutes to install and try. Then use Claude Code as you normally would, with two habits added:
`/learn` when you get corrected, `/recall` before digging into something cold. The background
reminders do the rest, and the prompt-time router quietly logs what it *would* have surfaced until
you choose to let it.

## Adopting into a setup you have already customized

This is a real path, not an afterthought — it is the case the author's own setup proved matters.

The same `./raememberit install` handles it. It leaves any command you have edited alone and says so,
detects memory hooks you already have and names them rather than quietly running both, and if your
`CLAUDE.md` already speaks of memories in your own words it does not touch it. On later updates it
names anything you changed in the tools and keeps your version next to the new one. Everything it
decides for you — the route, the flags — is documented in `ADVANCED.md` if you want to decide it
yourself.

## Known rough edges

Stated up front so none of them is a surprise:

- **Memories are written by a helper script, not by Claude's usual file-writing tool.** That looks
  indirect. It is deliberate: the corpus lives inside your config directory so the whole directory
  stays one portable unit, and Claude Code refuses its edit tools on paths inside a `.claude`
  directory as sensitive — no permission rule changes that. Bash is not gated, so
  `engine/mem-write.sh` is the write path. It also validates the schema, which the edit tool could not.
- **Updates are manual** — `git pull && ./raememberit update`. It shows what will change first, never
  touches memories, and keeps a copy of anything you changed in the tools rather than losing it.
- **The always-on index grows.** Every `feedback/` rule is injected into every context forever. In the
  setup this came from it grew about 10% a week, and once by 10% in a single afternoon. Watch it, and
  retire rules — adding is the easy half.
- **The starter rules are opinionated** and drawn from one person's engineering experience. Delete any
  you disagree with; that is a normal use of the tool, not a rejection of it.
- **Nothing is shared between people.** Everything is local and private to you. A shared team tier is a
  later stage, gated on problems that are not solved.

## How to stop

```bash
./raememberit uninstall                     # removes the tooling, KEEPS your memories
./raememberit uninstall --and-my-memories   # also deletes them, after you type "delete my memories"
```

It removes only its own hooks, commands and permission rules. Your settings, your own hooks and your
notes are left alone. If a tool cannot be backed out of cleanly it should not be adopted — so this is
tested, not merely promised.

## If something is wrong

Say so plainly, to whoever handed you this. Two things are worth more than the rest:

- **Where you stalled.** The first minute you were confused, and what you expected instead.
- **Anything irritating enough that you would turn it off.** Especially the hooks — "mildly annoying
  every session" compounds into uninstalled.
