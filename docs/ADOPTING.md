# Adopting raememberit

The honest version: what it is, what is known to be rough, and how to back out.

## What it is, in three sentences

It is a memory discipline for Claude Code: a small set of commands and hooks that make capturing a
fact cheap and looking one up reflexive. Everything it stores is plain markdown in a folder you own —
no database, no service, nothing leaves your machine. It grew out of one person's setup and has been
generalized so it can be someone else's.

## What the installer does for you

You do not need to read `QUICKSTART.md` first. A fresh install runs **guided**: it tells you what it
found, warns you if you already have memory hooks that would double up, shows each change before
making it, walks you through the first loop, and tells you how to get out. The quickstart is there if
you prefer reading, but it is not a prerequisite.

Fifteen minutes to install and try. Then use Claude Code as you normally would, with two habits added:
`/learn` when you get corrected, `/recall` before digging into something cold.

## Adopting into a setup you have already customized

This is a real path, not an afterthought — it is the case the author's own setup proved matters.

`install.sh` is for exactly this: it brings the engine and hooks and leaves your commands alone. If you
already have memory hooks of your own, guided mode **detects and names them** rather than quietly
running both, because two mechanisms doing the same job is the failure mode you will not notice until
your index is written twice.

The plugin is the other route, and it is the easier one if you have nothing to preserve. Its commands
are managed files, so it cannot carry commands you have edited. Pick by whether you have any.

## Known rough edges

Stated up front so none of them is a surprise:

- **Memories are written by a helper script, not by Claude's usual file-writing tool.** That looks
  indirect. It is deliberate: the corpus lives inside your config directory so the whole directory
  stays one portable unit, and Claude Code refuses its edit tools on paths inside a `.claude`
  directory as sensitive — no permission rule changes that. Bash is not gated, so
  `engine/mem-write.sh` is the write path. It also validates the schema, which the edit tool could not.
- **Updates are manual on the standalone path** — `git pull && ./install.sh`. Re-running is safe and
  never touches memories. The plugin updates itself.
- **The always-on index grows.** Every `feedback/` rule is injected into every context forever. In the
  setup this came from it grew about 10% a week, and once by 10% in a single afternoon. Watch it, and
  retire rules — adding is the easy half.
- **The starter rules are opinionated** and drawn from one person's engineering experience. Delete any
  you disagree with; that is a normal use of the tool, not a rejection of it.
- **Nothing is shared between people.** Everything is local and private to you. A shared team tier is a
  later stage, gated on problems that are not solved.

## How to stop

```bash
./uninstall.sh          # removes the tooling, KEEPS your memories
./uninstall.sh --purge  # also deletes them, after asking you to type DELETE
```

It removes only its own hooks, commands and permission rules. Your settings, your own hooks and your
notes are left alone. If a tool cannot be backed out of cleanly it should not be adopted — so this is
tested, not merely promised.

## If something is wrong

Say so plainly, to whoever handed you this. Two things are worth more than the rest:

- **Where you stalled.** The first minute you were confused, and what you expected instead.
- **Anything irritating enough that you would turn it off.** Especially the hooks — "mildly annoying
  every session" compounds into uninstalled.
