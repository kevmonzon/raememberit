# Quickstart

Fifteen minutes. This sets up an **isolated** trial that does not touch your normal Claude Code
configuration.

## 0. What you need

`jq`, `python3`, `git`, and Claude Code. The installer checks and tells you if something is missing.

## 1. Make an isolated config directory

Claude Code reads `CLAUDE_CONFIG_DIR`. Point it somewhere new and your usual setup is untouched —
settings, skills, commands, history, all of it stays where it is.

```bash
mkdir -p ~/raememberit-trial/{.claude,workspace}
export CLAUDE_CONFIG_DIR=~/raememberit-trial/.claude
```

Keep that `export` in mind: **it is per-shell.** A new terminal without it is back to your normal
setup, which is exactly the safety property you want.

**Pick the path now and leave it there.** Credentials are keyed to the config directory's path, so
moving or renaming it after you log in silently logs you out — you just have to `/login` again, but
it looks like a broken install when it happens. Measured, not guessed: renaming the directory during
development did exactly this, and moving it back restored the session.

## 2. Log in once

A fresh config directory has its own credentials, so it needs its own login. Same account.

```bash
cd ~/raememberit-trial/workspace
claude          # then run /login
```

## 3. Install

```bash
cd /path/to/raememberit
./raememberit install
```

It tells you what it found, asks what Claude should call you, shows what it is about to do, and
does it after you say yes. Three lines of its summary are worth reading:

- **`memory folder created`** — where your memories go: inside the config directory, so the whole
  thing stays portable.
- **`Claude can save memories without asking`** — memories are written by a small helper over Bash,
  because Claude Code refuses its edit tools on paths inside a `.claude` directory. `ADOPTING.md`
  explains it.
- **`added — Claude will now use memories on its own`** — the note it put in your `CLAUDE.md`, after
  showing it to you. Without that note the commands only work when you type them.

Want to see it without doing it: `./raememberit install --advanced --dry-run`.

## 4. Nothing — that step is done

Older versions asked you to paste a fragment into a `CLAUDE.md` by hand here. The installer now
offers to do it, shows the four lines first, and creates the file if you do not have one.

## 5. Your first ten minutes

Start Claude in the trial workspace, then:

**Look something up that is already there.** Eleven starter rules ship with it:

```
/recall tail exit code
```

You should get a rule about `| tail && echo "OK"` reporting success over a failing build. If you get
"no prior memory", something is wrong — please report it.

**Write your own first memory.** Take any non-obvious thing you worked out recently:

```
/learn --type reference "the staging deploy needs the VPN even though the docs do not say so"
```

Watch what it does. It should search for an existing memory covering the same ground *before*
writing, write through `mem-write.sh`, rebuild the index, and refuse to leave a near-duplicate
behind. If it writes blindly, that is a bug worth reporting.

If it instead tries the ordinary file-writing tool and gets refused as a "sensitive file", that is
also worth reporting — the command is supposed to know better.

**Find it again in a fresh session.** Quit, restart, and `/recall` the topic. That round trip —
written in one session, found in the next — is the whole product.

## 6. Then just work

For a week, two habits:

- **`/recall <topic>`** before investigating anything cold — a repo, an error, a tool.
- **`/learn`** the moment you are corrected, or something non-obvious costs you real effort. Mid-task,
  not at the end of the day.

And one judgement call, every time `/learn` writes a `feedback` memory: **pick a tier.**
`scope: global` stays in front of you always; `scope: domain` goes to the catalog where `/recall`
still finds it. Omitting the field means `global`, so the always-on tier grows by default — which is
the one thing here that degrades quietly. `memory/.index-status` prints the verdict after every
write.

Everything else is automatic.

## If something looks broken

```bash
./raememberit status                                                      # is it installed, current, healthy? read-only
bash $CLAUDE_CONFIG_DIR/raememberit/engine/rebuild-index.sh               # regenerate the indexes
python3 $CLAUDE_CONFIG_DIR/raememberit/engine/eval/run_eval.py --health   # structural check
claude --bare                                                             # hooks OFF: tells kit from harness
```

To check the write path by hand:

```bash
printf -- '---\nname: probe\ndescription: A probe memory to confirm the write path works end to end\nmetadata:\n  type: reference\n---\n\nbody\n' \
  | bash $CLAUDE_CONFIG_DIR/raememberit/engine/mem-write.sh reference probe
```

That last one matters: if a problem disappears under `--bare`, it is this tool's fault, not Claude
Code's.

## Getting out

```bash
./raememberit uninstall          # tooling gone, memories kept
```

Or simply `unset CLAUDE_CONFIG_DIR` and open a new terminal — your normal setup was never modified.
Your memories live inside the trial config directory, so deleting that directory removes everything
in one move.
