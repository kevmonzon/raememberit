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
./install.sh --user "<your name or handle>"
```

It prints every step. Two lines worth reading:

- **`corpus at …`** — where your memories go. Beside the config directory, not inside it. `PILOT.md`
  explains why.
- **`N raememberit hook group(s) wired`** — what it added to the settings file. It merges; it never
  replaces.

Want to see it without doing it: `./install.sh --dry-run`.

## 4. Point Claude at the memory instructions

The installer writes a fragment and does **not** edit any `CLAUDE.md` for you. Add it:

```bash
cat $CLAUDE_CONFIG_DIR/raememberit/INSTRUCTIONS-fragment.md >> ~/raememberit-trial/workspace/CLAUDE.md
```

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

Watch what it does. It should check for an existing memory covering the same ground *before*
writing, then rebuild the index, then refuse to leave a near-duplicate behind. If it writes blindly,
that is a bug worth reporting.

**Find it again in a fresh session.** Quit, restart, and `/recall` the topic. That round trip —
written in one session, found in the next — is the whole product.

## 6. Then just work

For a week, two habits:

- **`/recall <topic>`** before investigating anything cold — a repo, an error, a tool.
- **`/learn`** the moment you are corrected, or something non-obvious costs you real effort. Mid-task,
  not at the end of the day.

Everything else is automatic.

## If something looks broken

```bash
bash $CLAUDE_CONFIG_DIR/raememberit/engine/rebuild-index.sh                     # regenerate the indexes
python3 $CLAUDE_CONFIG_DIR/raememberit/engine/eval/run_eval.py --health         # structural check
claude --bare                                                                   # run with hooks OFF, to tell kit from harness
```

That last one matters: if a problem disappears under `--bare`, it is this tool's fault, not Claude
Code's.

## Getting out

```bash
./uninstall.sh          # tooling gone, memories kept
```

Or simply `unset CLAUDE_CONFIG_DIR` and open a new terminal — your normal setup was never modified.
