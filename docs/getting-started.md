# Getting started

Fifteen minutes: install, try one round trip, then carry on working with two habits added.

## What you need

- [Claude Code](https://claude.com/claude-code), signed in
- `git`, `jq` and `python3` — the installer checks and tells you what is missing and how to get it
- macOS or Linux. The scripts target bash 3.2, which is what macOS ships.

## Install

```bash
git clone <this repository>
cd raememberit
./raememberit install
```

The installer looks at your computer, asks what Claude should call you, shows you what it is about
to do, and does it after you say yes. In plain terms it will:

1. put the tools in `<config>/raememberit`
2. create your memory folder at `<config>/memory`, with eleven starter rules
3. let Claude save memories there without asking you every time
4. add the background reminders — all quiet unless something needs attention
5. offer to add a four-line note to `<config>/CLAUDE.md` so Claude knows memories exist — shown
   first; the file is created if you do not have one; skipped if yours already speaks of memories

Nothing else on your computer is touched, and `./raememberit uninstall` undoes all of it while
keeping your memories.

Already have a customized setup? The same command handles it: it leaves any command you have
edited alone and says so, detects memory hooks you already have rather than quietly running both,
and does not touch a `CLAUDE.md` that already mentions memories in your own words. Details in
[Advanced](advanced.md).

Want to see it without doing it: `./raememberit install --advanced --dry-run`.

## The first ten minutes

Start Claude, then:

**Look something up that is already there.** Eleven starter rules ship with it:

```
/recall tail exit code
```

You should get a rule about `| tail && echo "OK"` reporting success over a failing build. If you get
"no prior memory", something is wrong — [Troubleshooting](troubleshooting.md).

**Write your own first memory.** Any non-obvious thing you worked out recently:

```
/learn the staging deploy needs the VPN even though the docs do not say so
```

Watch what it does. It should search for an existing memory covering the same ground *before*
writing, write through the helper, rebuild the index, and refuse to leave a near-duplicate behind.
If it writes blindly, or reaches for the ordinary file-writing tool and gets refused as a "sensitive
file", both are worth reporting — the command is supposed to know better.

**Find it again in a fresh session.** Quit, restart, and `/recall` the topic. Written in one session,
found in the next — that round trip is the whole product.

## Then just work

Two habits:

- **`/recall <topic>`** before investigating anything cold — a repo, an error, a tool, a ticket.
- **`/learn`** the moment you are corrected, or something non-obvious costs you real effort.
  Mid-task, not at the end of the day.

Everything else is automatic, and the [cadence](cadence.md) page says what little is not.

One judgement call, every time `/learn` writes a `feedback` memory: **pick a tier.** `scope: global`
stays in front of Claude always; `scope: domain` goes to the catalog where `/recall` still finds it.
Omitting it means `global`, so the always-on tier grows by default — the one thing here that degrades
quietly. [Configuration](configuration.md) explains the budget that guards it.

## Trying it in isolation first

Point `CLAUDE_CONFIG_DIR` at a throwaway directory and Claude Code relocates its entire config
there — settings, commands, corpus, session history:

```bash
mkdir -p ~/raememberit-trial/{.claude,workspace}
export CLAUDE_CONFIG_DIR=~/raememberit-trial/.claude     # per shell; a new terminal is back to normal
cd ~/raememberit-trial/workspace && claude               # then /login, once — credentials are per config dir
cd /path/to/raememberit && ./raememberit install --config-dir ~/raememberit-trial/.claude
```

Pick the path and leave it: credentials are keyed to it, and renaming the directory logs you out.
To get out: `unset CLAUDE_CONFIG_DIR` and open a new terminal; deleting the trial directory removes
everything in one move. What isolation does and does not guarantee is in
[Development](development.md#testing-in-isolation).
