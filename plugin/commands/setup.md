---
description: Set up raememberit — detect what is already here, seed the corpus, add the one permission rule, and walk the first loop. Run this once after installing the plugin.
---

# Set up raememberit

You are onboarding someone who has just installed this plugin. **They have not read any
documentation, and they should not need to.** This command is the installer.

`install.sh --plugin` does the file changes. Your job is the part a script cannot do: explain what is
about to change before it changes, in their situation rather than in general, and stop when a step
needs a decision. Work through the steps in order. **Do not batch them into one message** — each one
that changes something gets its own confirmation.

Throughout: `PLUGIN="${CLAUDE_PLUGIN_ROOT}"`, and the config dir is
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. If `CLAUDE_PLUGIN_ROOT` is not set in a shell you run, find the
plugin with `claude plugin list` rather than guessing at a path — the install path carries a version
component and guessing it is how this breaks after an update.

## 1. Report what you found, before touching anything

Run the installer in **dry-run** mode and read its output. It changes nothing:

```bash
bash "$PLUGIN/install.sh" --plugin --dry-run --no-guided
```

Then tell them, in plain sentences, which of these three situations they are in:

- **Fresh** — no corpus. The interesting case; everything below applies.
- **Existing corpus** — memories already at `<config>/memory`. Say the count. **Nothing will be
  overwritten**; the installer tops up only missing scaffold, and only when asked.
- **They already have memory hooks of their own.** Look for this specifically:

  ```bash
  jq -r '(.hooks // {}) | to_entries[] | .key as $e | .value[]? | .hooks[]? | .command // ""
         | select(test("memory|MEMORY")) | select(test("raememberit") | not)' \
     "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null
  ```

  If that prints anything, **stop and say so before continuing.** They are about to run two
  mechanisms that do the same job: two index rebuilds, two injections, two reminders. It does not
  error — it just doubles, quietly, which is why it has to be named now rather than discovered later.
  Ask whether to remove theirs, keep both deliberately, or stop here.

## 2. The write helper needs a stable path — check it exists

Memories are written by a script over Bash, not by the Edit tool, because Claude Code refuses its
edit tools on paths inside a `.claude` directory. Say that plainly; it looks indirect until explained.

```bash
find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data" -maxdepth 3 -path '*/bin/mem-write.sh'
```

**Empty result is normal on a first run.** That wrapper is placed by the plugin's `SessionStart` hook,
so it appears after one restart. If it is missing, tell them: finish the other steps now, restart, then
run `/raememberit:setup` again to add the permission rule. Do not try to create it by hand.

## 3. Show the permission rule, then add it

Show them the exact rule the installer will add, and why it matters: **without it, every single memory
write asks for approval**, and a tool that interrupts you every time it remembers something is a tool
you will stop using. It names one absolute, version-free path — it survives plugin updates and grants
nothing else.

Get a yes, then run it for real:

```bash
bash "$PLUGIN/install.sh" --plugin --no-guided --user "<their name, or omit>"
```

This also seeds the corpus if absent (scaffold plus 11 starter rules), writes the instruction
fragment, and rebuilds the indexes. It never wires hooks — the plugin already supplies those, and
adding them here would fire each one twice.

## 4. Offer the instruction fragment — never write it unasked

The installer writes `<corpus>/INSTRUCTIONS-fragment.md` and deliberately **does not** touch their
`CLAUDE.md`. Show them what it says, then offer to append it.

Be honest about the stake: without it, the commands still work when typed, but they will not fire on
their own — and firing on their own is most of the value. With it, `/recall` runs before you
investigate something cold and `/learn` runs when you are corrected, without being asked.

If they say yes, append it with Bash (`cat >>`), not the Edit tool — their `CLAUDE.md` may sit inside
`.claude`, where edit tools are refused. Show the target path first. If they say no, leave it; say
where the fragment is and move on without pressing.

## 5. Tell them what the hooks will do to their session

Surprises here are what get a tool uninstalled. Be specific:

- **every new context** — the always-on index is injected once, then suppressed until it resets
- **session start** — if enough logs have piled up, a pattern sweep is *offered*, never run
- **before compaction** — a nudge to capture memory first
- **session end** — both indexes regenerate from frontmatter
- **session end with no log today** — a reminder

Name the last one explicitly and say how to change it: the **Require an interaction log** option can be
set to `strict`, which *blocks a session from ending*, or `off`, which silences it. Default is a
reminder. Someone who discovers a blocked session without having been warned concludes the tool is
broken.

## 6. Walk the first loop — on something real

Do not demonstrate with a toy. Ask them for one thing they actually worked out recently, and capture
that. A real round trip is the only thing that makes the value legible; a test memory proves the
plumbing and teaches nothing.

1. `/raememberit:learn <the thing>` — and have them watch it search for an existing memory **before**
   writing. That search is the discipline. If it writes blindly, that is a bug worth reporting.
2. Then, in a **new session**, `/raememberit:recall <that topic>`. Written in one session, found in the
   next — that is the product. Everything else is plumbing.

Say which tier it landed in: `feedback/` is injected into every context forever, `project/` and
`reference/` are looked up on demand. The always-on tier has no natural ceiling, so rules deserve more
scrutiny than notes.

## 7. How to get out, before they need it

```
claude plugin uninstall raememberit
```

Their **memories are not in the plugin** — they are at `<config>/memory`, and uninstalling cannot
touch them. Say why: a plugin directory is replaced on every update, so a growing corpus could never
have lived there. Two things to clear by hand for a clean sweep: the permission rule in settings, and
the fragment if they pasted it into `CLAUDE.md`.

## Finally

Confirm what changed, as a short list of paths. Then stop. Do not volunteer further configuration —
they have enough to start, and the rest is discoverable.
