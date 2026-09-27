# Pilot brief

You have been asked to try **raememberit** for about a week. This page is the honest version: what
it is, what we want to learn, what is already known to be rough, and how to stop.

## What it is, in three sentences

It is a memory discipline for Claude Code: a small set of commands and hooks that make capturing a
fact cheap and looking one up reflexive. Everything it stores is plain markdown in a folder you own
— no database, no service, nothing leaves your machine. It grew out of one person's setup and is
being generalized; you are the first person other than its author to run it.

## What we actually want to learn

Not "does it work" — there are 99 automated assertions for that, and they pass. What we cannot test
is the part you are for:

1. **Where do you stall?** The first minute you are confused, stop and write down what you expected.
   That sentence is the most valuable thing this pilot can produce.
2. **Does capture actually feel cheap?** The whole design bets that `/learn` is fast enough to run
   mid-task. If you find yourself deferring it, that bet is wrong and we need to know.
3. **Is anything annoying enough that you would turn it off?** Especially the hooks. Say so bluntly;
   "mildly irritating every session" compounds into uninstalled.
4. **Does `/recall` ever actually save you time?** If after a week it has not, that is a finding, not
   a failure on your part.

Negative findings are the point. A week of "this did nothing for me" is a useful week.

## What is explicitly NOT being asked of you yet

**Do not try to integrate this with your existing Claude Code setup.** How it coexists with
configuration you already have is a separate conversation we have deliberately not had yet. For the
pilot, run it in a clean config directory — `QUICKSTART.md` shows how, and it keeps your normal setup
untouched.

Also not being asked: sharing memories with anyone. Everything is local and private to you. A shared
team tier is a later stage and is gated on problems we have not solved.

## Known rough edges — please do not spend time reporting these

We already know:

- **Memories are written by a helper script, not by Claude's usual file-writing tool.** That looks
  indirect. It is deliberate: the corpus lives inside your config directory so the whole directory
  stays one portable unit, and Claude Code refuses its edit tools on paths inside a `.claude`
  directory as sensitive — no permission rule changes that. Bash is not gated, so
  `engine/mem-write.sh` is the write path. It also validates the schema, which the edit tool could
  not.
- **Updates are manual** — `git pull && ./install.sh`. Re-running is safe and never touches memories.
- **The always-on index grows.** Every `feedback/` rule is injected into every context forever. In
  the setup this came from it grew about 10% a week. If yours starts feeling heavy, that is the
  thing to tell us about.
- **The starter rules are opinionated** and drawn from one person's engineering experience. Delete
  any you disagree with — that is a normal use of the tool, not a rejection of it.
- **It is not published.** Team-first, on purpose.

## Time

Fifteen minutes to install and try. Then just use Claude Code as you normally would for a week, with
two habits added: `/learn` when you get corrected, `/recall` before digging into something cold.

## How to stop

```bash
./uninstall.sh          # removes the tooling, KEEPS your memories
./uninstall.sh --purge  # also deletes them, after asking you to type DELETE
```

It removes only its own hooks, commands and permission rules. Your settings, your own hooks and your
notes are left alone. If a pilot cannot be backed out of cleanly, it should not be agreed to — so
this is tested, not merely promised.

## Reporting back

Use `docs/pilot-feedback.md`. It is short on purpose. Raw and blunt beats polished.
