# Troubleshooting

Start here:

```bash
./raememberit status
```

Every warning it can show, and the fix.

| `status` says | Meaning | Fix |
|---|---|---|
| `this download is X — run: ./raememberit update` | the checkout is newer than the install | `./raememberit update` |
| `no background reminders found` | the hooks plugin is missing or settings lost their entries | `./raememberit update` |
| `Claude will be asked before every memory save` | the permission rule for the write helper is gone | `./raememberit update`; on the plugin route, restart Claude once, then `/raememberit:setup` again |
| `nothing tells Claude that memories exist` | no `CLAUDE.md` mentions the corpus, `/recall` or `/learn` | `./raememberit update` offers the note; or write your own lines |
| `over its N KB limit` | the always-on tier is past the budget and heading for the ceiling | demote rules with `scope: domain`, then rebuild |
| `raememberit is not installed` | nothing at the config dir it looked at | `./raememberit install`, or `--config-dir` if yours is elsewhere |

## Symptoms without a warning

**`/recall` says "no prior memory" about something you know is there.** Literal substring matching
missed the spelling. Search the variants the command's step 1 asks for; for a two- or three-letter
term use `grep -w`. If the catalog line itself is missing, rebuild:

```bash
bash <config>/raememberit/engine/rebuild-index.sh
python3 <config>/raememberit/engine/eval/run_eval.py --health
```

**The session starts with a tripwire message about truncated injections.** The always-on index
outgrew the harness's ceiling in a recent session. If the message says the last rebuild passed its
budget, it is historical and clears itself in 48 hours. If it says `OVER`, demote feedback memories
with `scope: domain` until `.index-status` says `OK`.

**Claude tried the Write tool on a memory and was refused as a "sensitive file".** Not a broken
install: paths inside `.claude` are gated for that tool and no permission rule changes it. The
commands are supposed to use `mem-write.sh` over Bash; if one reached for the wrong tool, port the
current template (`./raememberit status --commands`).

**Every session ends with "Hook cancelled".** An old engine ran the index rebuild in the foreground
and overran the exit budget. Fixed in 0.5.2's successor; `./raememberit update`.

**Hooks fire twice — the index injected twice, two reminders.** Two routes are wired at once, or
predecessor hooks of your own remain. `./raememberit status` names your own; the installer refuses to
double its own. See [Advanced](advanced.md#two-routes-one-implementation).

**`/learn` exits 3 after writing.** The duplicate gate: the write left a near-duplicate pair. The
file is on disk; merge it into the existing one rather than retyping. `RAEMEMBERIT_DUPES=warn` while
you pay down a corpus that arrived with duplicates.

**Is it the kit or Claude Code?** `claude --bare` starts with hooks off. If a problem disappears
under it, it is this tool's; if it persists, it is not.

## Testing in isolation

Point `CLAUDE_CONFIG_DIR` at a throwaway directory ([Getting started](getting-started.md#trying-it-in-isolation-first)).
Two things to know before trusting a sandbox:

- **It isolates writes, not reads.** `CLAUDE_CONFIG_DIR` does not change `$HOME`, so a session can
  still read the default config at its absolute path — and one did, absorbing another setup's voice.
  State the boundary in the sandbox's own `CLAUDE.md`.
- **An ambient `RAEMEMBERIT_MEMORY_DIR` wins over `CLAUDE_CONFIG_DIR`.** If your real
  `settings.json` publishes it, a sandbox session that sets only the config dir still writes the real
  corpus. Set both, and check the real `MEMORY.md`'s mtime afterwards. The installer and uninstaller
  ignore the ambient variable when `--config-dir` is explicit, for exactly this reason.

## Reporting a problem

The most useful thing: the first moment you were confused — what you expected and what happened
instead, written while it is fresh. Second: anything irritating enough that you would turn it off,
especially a hook. Attach the log the front door names when something fails.
