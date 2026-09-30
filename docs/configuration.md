# Configuration

A knob exists wherever an adopted setup might reasonably differ. Set them in `settings.json` under
`env` — never by editing a script, because an update replaces the whole engine directory (and keeps
your patched copy aside, but does not carry it forward).

```json
{ "env": { "RAEMEMBERIT_REQUIRE_LOG": "strict", "RAEMEMBERIT_AUTORECALL": "inject" } }
```

On the plugin route the same values are typed options in the plugin's manifest and reach the engine
as `CLAUDE_PLUGIN_OPTION_*`; an explicit `RAEMEMBERIT_*` in `env` wins over an option.

## Knobs

| Variable | Default | Effect |
|---|---|---|
| `RAEMEMBERIT_REQUIRE_LOG` | `warn` | at turn end with no session log today: `warn` reminds · `strict` blocks the stop · `off` silent |
| `RAEMEMBERIT_CORRECTIONS` | `nudge` | the correction detector: `nudge` logs and adds one line naming `/learn`, and reminds once at Stop after two corrections with nothing learned · `strict` makes that reminder block · `shadow` logs only · `off` |
| `RAEMEMBERIT_AUTORECALL` | `shadow` | the router's memory half: `shadow` logs what it would surface to `memory/.recall-log` · `inject` adds the best few catalog lines to context · `off` |
| `RAEMEMBERIT_SKILLROUTER` | `shadow` | the router's skill half: `shadow` logs matching commands and skills to `memory/.skill-log` · `inject` names them in context · `off` |
| `RAEMEMBERIT_AUTORECALL_BUDGET` | `1500` | byte ceiling for the injected memory block |
| `RAEMEMBERIT_ROUTER_MAX` | `3` | entries per injected block |
| `RAEMEMBERIT_SWEEP_THRESHOLD` | `15` | new session logs before a pattern sweep is offered |
| `RAEMEMBERIT_RECENT_N` | `8` | session logs listed in the always-on index |
| `RAEMEMBERIT_DUPES` | `block` | the duplicate gate after a write: `block` exits 3 · `warn` reports · `off` skips. Start on `warn` when adopting a corpus that already has duplicates |
| `RAEMEMBERIT_ALWAYS_ON_BUDGET` | `12000` | byte ceiling for the always-on index; over it, the index is still installed and `.index-status` records `OVER` |
| `RAEMEMBERIT_TRIPWIRE` | `on` | `off` disables the session-start truncation check |
| `RAEMEMBERIT_TRIPWIRE_WINDOW_H` | `48` | how far back the tripwire looks; also how long a warning takes to clear itself |
| `RAEMEMBERIT_PRECOMPACT_MSG` | (built-in) | the wording of the pre-compaction reminder |
| `RAEMEMBERIT_MEMORY_DIR` | `<config>/memory` | corpus location; the installer publishes it |
| `RAEMEMBERIT_QUERIES` | `<corpus>/eval/queries.json` | the query file the eval harness scores |
| `RAEMEMBERIT_DENYLIST` | `.denylist.local.txt` | a private vocabulary file for the sanitization gate |

`RAEMEMBERIT_REQUIRE_LOG` defaults to **warn**, not strict, on purpose. The setup this came from
blocked the stop; that is a reasonable choice for its author and a hostile default for anyone else —
a hook that refuses to let someone end their session is the fastest route to the kit being
uninstalled.

Three more variables are configuration rather than knobs — `RAEMEMBERIT_USER`,
`RAEMEMBERIT_PERSONA_FILE`, `RAEMEMBERIT_VOCAB_FILE`. The installer sets them from `--name` (or
`--user`, `--persona`, `--vocabulary` on `install.sh`) and remembers them in `raememberit/.config`,
so a re-run inherits them.

## The two tiers

`MEMORY.md` is injected into every context window; `MEMORY-CATALOG.md` is read on demand. Only
`feedback` memories can land in the always-on tier, and each declares which:

```yaml
metadata:
  type: feedback
  scope: global   # or: domain
```

`global`: a standing rule that changes behaviour on **any** task, whatever the repo, language or
tool. `domain`: bound to one of those; demoted to the catalog, where `/recall` and the router still
find it. The test that decides: *would I want this in front of Claude before it knows what the task
is?* Consent and epistemic rules usually pass; craft advice about one artifact usually does not.

**An absent `scope` means `global`**, deliberately — defaulting absence the other way would empty the
always-on tier on the first rebuild after upgrading an older corpus, a far worse failure than carrying
one rule too many. But omitting it is not the same as choosing it: decide, then write.

The tier has a byte budget because the harness silently declines to inject an oversized payload
([how it works](how-it-works.md#the-one-failure-that-looks-like-success)). `rebuild-index.sh`
records the verdict in `memory/.index-status`; the tripwire surfaces it at the next session start.

## Domain tags

Any memory may name the repo, tool or ticket prefix it is about:

```yaml
metadata:
  type: reference
  domain: payments, mysql
```

The write helper enforces the shape (kebab-case tokens, comma-separated). The catalog line shows it,
so `/recall` greps catch it, and `rebuild-index.sh` writes `memory/.domain-index`, one row per
(domain, memory), which is what lets the router surface a memory when the working directory's name
or the prompt names its domain — without opening every file. A project or reference memory about one
repo should carry it; a global rule should not.

## The router

`context-router.sh` runs on every prompt: tokens from the prompt, the working directory's name and
any ticket key, scored against every catalog line, the domain index, and the `description:` of every
installed command and skill. No model call; tens of milliseconds; each hit surfaced once per session.

| Mode | Memories half | Skills half |
|---|---|---|
| `shadow` (default) | logs the would-be hits to `memory/.recall-log` | logs to `memory/.skill-log` |
| `inject` | adds up to `ROUTER_MAX` catalog lines, under `AUTORECALL_BUDGET` bytes, with paths | names the matching commands and skills |
| `off` | nothing | nothing |

The rhythm is: shadow for a week or two, then `/memory-audit` §7 samples the log and reports a
precision ratio, then flip. `/recall` writes the same log for manual sweeps, so together they are
the only record of which memories are ever read — the audit uses it to shortlist memories nobody has
retrieved in months, which is how the corpus prunes itself instead of only growing.

## The starter rules

Eleven generic engineering rules ship in `starter/feedback/`, each with its evidence, and are seeded
into a fresh corpus. Delete any you disagree with; that is a normal use of the tool. The corpus
records which ones it received (`memory/.seeded-starters`), so a rule you delete never comes back on
an update. `starter/optional/` holds working preferences rather than engineering truths — copy one in
if you want it.

## Persona and vocabulary

`install.sh --persona FILE` appends a file to the imported instructions — a voice, house terms, local
conventions. `--vocabulary FILE` gives `/recall`'s query expansion a list of your project's words.
Both are remembered for re-runs.
