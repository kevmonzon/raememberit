# Lifecycle

How every feature in this kit comes alive, in what order, and what it leaves behind.

`README.md` says *what* each part is. This says *when* each part runs, what state it reads,
what state it writes, and which other feature depends on that state existing. Read it when
adding a feature (where does it hook in?), when one misfires (which stage owns it?), or when
deciding whether something can be removed (who reads its output?).

Nothing here is hand-maintained truth about the wiring: the hook table lives in
`engine/settings.fragment.json`, and `tools/test-docs.sh` fails the build when the docs and
the wiring disagree.

---

## The whole arc, at a glance

```
  ACQUIRE ─▶ INSTALL ─▶ ┌───── PER SESSION ─────────────────────────────┐ ─▶ MAINTAIN ─▶ UPGRADE ─▶ EXIT
                        │                                               │
                        │  SessionStart ─▶ prompt ─▶ work ─▶ compact ─▶ │
                        │       │            │        │        │        │
                        │   place-shim   inject-   /recall  precompact  │
                        │   skillmine-    memory   /learn    -notice    │
                        │   nag                    mem-write  rearm     │
                        │   tripwire                                    │
                        │                                               │
                        │  Stop ─▶ SessionEnd ─▶ rebuild-index          │
                        │  require-log  close-log                       │
                        └───────────────────────────────────────────────┘
```

Two loops, not one. The **inner loop** is a session: memory is injected, consulted, written,
and re-indexed. The **outer loop** is the corpus's own housekeeping — reflect, audit, mine,
eval — which runs on a cadence of days, not prompts.

---

## Stage 0 — Acquisition

Two routes into a config directory, and they carry different amounts of the kit.

| | As a plugin (`plugin/`) | Via `install.sh` |
|---|---|---|
| Delivers | engine + hooks | engine + hooks + commands + corpus scaffold + starter rules |
| Wiring | `plugin/hooks/hooks.json`, auto-loaded from `<config>/skills/raememberit/` | merged into `settings.json` |
| Paths | `${CLAUDE_PLUGIN_ROOT}`-relative | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`-relative |
| Config | `userConfig` in `plugin.json` | `--user`, `--persona`, `--vocabulary`, plus `env` knobs |
| Cannot supply | permission rules, settings `env` | — |

`plugin/hooks/hooks.json` is **generated** from `engine/settings.fragment.json` by
`tools/gen-plugin-hooks.sh`; a test asserts the two stay identical. One mechanism, two
descriptions, is a drift surface this project has been bitten by three times.

## Stage 1 — Install

`install.sh` runs as a sequence of named phases, each of which either changes something and
says so, or reports that nothing needed changing:

```
Preflight ─▶ Configuration ─▶ Target ─▶ Engine ─▶ Corpus ─▶ Commands
          ─▶ Instructions ─▶ Hooks ─▶ Index ─▶ Done
```

What each phase establishes, and what later depends on it:

| Phase | Writes | Depended on by |
|---|---|---|
| Preflight | nothing — detects **predecessor memory hooks** | the guided warning; adopting alongside them doubles every hook's work |
| Corpus | `<config>/memory/` from `scaffold/`, plus `starter/` rules | every read and write from here on |
| Commands | `recall`, `learn`, `memory-reflect`, `memory-audit`, `skill-mine` + `.installed-commands` manifest | Stage 7's upgrade policy |
| Instructions | `raememberit/INSTRUCTIONS-fragment.md` — **never** your `CLAUDE.md` | whether the commands fire unprompted |
| Hooks | merged hook entries, `Bash(...)` allow rule for the write helper, `env.RAEMEMBERIT_MEMORY_DIR` | every stage below |
| Index | first `MEMORY.md` / `MEMORY-CATALOG.md` | Stage 3's injection |

A fresh interactive install runs **guided**: it surveys, warns, shows the diff it is about to
apply, and walks the first `recall → learn → recall` round trip before you are left alone with
it. `--dry-run` reports without touching anything; `--no-guided` skips the walkthrough.

The install is **idempotent** — re-running it is the upgrade path (Stage 8).

## Stage 2 — Session start

| Hook | Event | What it does |
|---|---|---|
| `place-shim.sh` | `SessionStart` | plugin route only: regenerates a version-free wrapper at `$CLAUDE_PLUGIN_DATA/bin/mem-write.sh` |
| `skillmine-nag.sh` | `SessionStart` | counts interaction logs newer than `.last-sweep`; **offers** a pattern sweep past `RAEMEMBERIT_SWEEP_THRESHOLD` (15) |
| `truncation-tripwire.sh` | `SessionStart` | reports sessions whose index injection the harness **truncated**, detected from the artifacts it leaves rather than from any size guess |

`place-shim.sh` exists for one reason: a plugin lives under a path carrying its **version**, a
permission rule must name an absolute path, and so a rule aimed inside the plugin would be
invalidated by every update. The shim is rewritten on every session start, which makes it
self-healing — the root moves, the rule never does. On the standalone install it exits
immediately; the engine is already at a stable path.

`skillmine-nag.sh` only *offers*. It never runs the sweep, and it stays silent when nothing has
been logged yet.

`truncation-tripwire.sh` exists because the injection has a failure mode that looks exactly like
success. Past an undocumented size ceiling the harness does not inject a hook's
`additionalContext`: it writes the payload to
`projects/<proj>/<session>/tool-results/hook-*-additionalContext.txt`, hands the model a short
preview and that path, and returns no error. The hook still exits 0. Measured on a real corpus, 13
consecutive sessions delivered 8 of 71 index entries this way with nothing anywhere reporting it.

It deliberately does **not** guard a byte threshold. The ceiling is undocumented, was only ever
observed from below, and lives in a self-updating binary, so a constant would encode a guess about
a proxy. Instead it counts those artifacts inside a rolling window, confirms each one is this
hook's payload before blaming it, and reports. The window is also the reset: once the payload fits
again no new artifacts appear and the warning ages out on its own, with no marker file to clear.

Its advice tracks `<corpus>/.index-status`, not the artifact count — the artifacts are historical
by construction, so an already-trimmed index gets told the warning is historical rather than being
told to trim again. An alarm that keeps crying about a fixed fault is one people learn to ignore.

## Stage 3 — Prompt time: injection

`inject-memory.sh` fires on `UserPromptSubmit` and injects `MEMORY.md` — **once per context
window**, not once per prompt. The mechanism is a guard file at
`${TMPDIR}/raememberit-injected-<session_id>`: present, the hook exits; absent, it injects and
creates it.

It also prepends a **configuration preamble** — how to address you, where the corpus is, and
that writes go through `mem-write.sh` over Bash. That preamble lives in the hook rather than in
the command files because a plugin's commands are managed files replaced on every update, and
across the 39 official plugins no command reads a `CLAUDE_PLUGIN_OPTION_*`. Options reach
processes; the hook is a process.

What gets injected is only the **always-on tier**:

| Tier | File | Contents |
|---|---|---|
| always-on | `MEMORY.md` | profile + every `feedback/` rule + the newest `RAEMEMBERIT_RECENT_N` (8) interaction logs |
| on-demand | `MEMORY-CATALOG.md` | every `project/` + `reference/` memory — pointers, pulled only when a topic arises |

The split is the whole design. Context injected into every prompt is the scarcest resource in
the system, so it is bounded by policy (`feedback/` is small and standing) and by knob
(`RAEMEMBERIT_RECENT_N`), while everything unbounded sits behind Stage 4.

## Stage 4 — Retrieval: `/recall`

The bridge to the on-demand tier. Run **before** investigating any repo, ticket, error string,
tool or environment cold — the working assumption is that a relevant memory exists until recall
says otherwise.

```
query ─▶ expand (vocabulary) ─▶ grep catalog + interaction-log history ─▶ rank ─▶ report
```

Query expansion is not decoration: `starter/baseline.json` freezes the measured gap at
**literal 8/12 vs expanded 12/12**. That six-point spread *is* the value of the expansion step,
and a change to any starter rule's `description:` that breaks retrieval fails the test run.

Exact corpus counts appear nowhere in the command file — they drift within days.
`engine/rebuild-index.sh` prints the live figures.

## Stage 5 — Capture: `/learn` and the write path

Capture is deliberately cheap enough to run mid-task. The end-of-session sweep loses the
nuance: by then you remember *that* you were corrected, not the sentence that corrected you.

```
trigger ─▶ classify ─▶ find-similar.py ─▶ mem-write.sh ─▶ schema gate ─▶ dupe gate ─▶ rebuild-index
```

**Triggers that fire without being asked:** a correction ("no", "actually", "next time",
"always", "never"), a stated preference, a non-obvious fact that cost real effort, or an
explicit "remember this". Not fired for anything the repo already records.

**`find-similar.py`** is a script rather than a prose step on purpose. The prose version — "check
for an existing file first" — had a measured failure rate: three memories describing one
identical fact, written inside a four-hour window. A command whose output you must answer to is
harder to skip than a paragraph you must remember.

**`mem-write.sh`** is the only write path, and it is invoked over Bash because of a hard
constraint:

| | inside a `.claude` directory |
|---|---|
| Read tool | not gated |
| Edit / Write tools | **refused per file** — an allow rule does not override it |
| Bash | **works** |

The side benefit turned out larger than the workaround. A helper can **enforce** schema, which
the Write tool never could. It refuses:

- a `name:` that does not match the filename
- a `description:` under 20 characters — it *is* the routing signal
- a missing `metadata.type:`
- a `feedback` or `project` entry with no **Why:** / **How to apply:**
- an overwrite without `--update`
- a slug that is not lowercase-kebab-case

Then it rebuilds both indexes and exits non-zero if the write left a near-duplicate behind
(`RAEMEMBERIT_DUPES` = `block` | `warn` | `off`).

Interaction logs take the same path (`mem-write.sh log <topic>`), are dated
`YYYY-MM-DD-HH-MM-topic.md`, and **append** rather than duplicate when a log for the same topic
already exists today.

## Stage 6 — Compaction

| Hook | Event | Effect |
|---|---|---|
| `precompact-notice.sh` | `PreCompact` (auto) | reminds the assistant to capture the log and durable memories *before* they compress away |
| `rearm-inject.sh` | `PostCompact` | deletes the injection guard, so the fresh context re-injects on the next prompt |

The re-arm is what makes injection survive compaction without a cron or a stale-timestamp
heuristic: the guard is per-session-id, and the only thing that removes it is a context
boundary.

`RAEMEMBERIT_PRECOMPACT_MSG` replaces the wording entirely. That knob exists because the
message *is* the whole content of that hook, an adopted setup may have phrasing worth keeping,
and editing the script would not survive an upgrade — `install.sh` replaces the whole `engine/`
directory.

## Stage 7 — Session end

```
Stop ────────────▶ require-log.sh        warn (default) | strict | off
SessionEnd(clear)▶ close-log.sh          stamps a /clear boundary into today's latest log
                 ▶ rearm-inject.sh       next context re-injects
SessionEnd(all) ─▶ rebuild-index-hook.sh regenerates both indexes from frontmatter (30s)
```

`RAEMEMBERIT_REQUIRE_LOG` defaults to **warn**, not strict. The setup this was extracted from
blocked the stop; that is a reasonable choice for its author and a hostile default for anyone
else — a hook that refuses to let someone end their session is the fastest route to the kit
being uninstalled. Strict remains one env var away.

`rebuild-index.sh` is the closing invariant: **indexes are derived, never hand-edited.** Change
a memory's `name:` or `description:` and re-run; the empty-corpus case (every fresh install) is
handled with `find` rather than `ls` precisely because a glob failure under `pipefail` would
have produced a truncated index and no catalog, silently, behind the hook's `|| true`.

## Stage 8 — The outer loop: maintaining the corpus

Four features that operate on the corpus rather than inside a session.

| Command | Cadence | Reads | Produces | Writes anything? |
|---|---|---|---|---|
| `/memory-reflect` | end of session, or pre-compaction | the conversation | the interaction log + any durable memories `/learn` missed | yes |
| `/memory-audit` | periodic | the whole corpus | findings table: index integrity, malformed frontmatter, duplicates, contradictions, shipped work still in `project/` | **no — proposes only** |
| `/skill-mine` | offered past 15 new logs | only logs newer than `.last-sweep` | ranked skill candidates, promoted at the **2nd** recurrence | yes, on per-candidate approval |
| `engine/eval/run_eval.py` | on demand + in CI | corpus + `eval/queries.json` | hit@1 per strategy, plus `--health` | no |

If `/learn` has been doing its job, `/memory-reflect` is boring — most durable facts are
already written, and what remains is the narrative, which exists nowhere else.

`/skill-mine` reads **only the delta**. Re-reading every log to rediscover patterns already
triaged is pure waste, and new signal lives in the delta anyway. The watermark at
`.last-sweep` is the entire mechanism.

`/memory-audit` writes nothing. Every check in it exists because it once found a real defect
that no retrieval improvement could have fixed — the worst observed being three files
describing one fact within four hours, and **62% of `project/` memories describing work that
had already shipped**.

## Stage 9 — Upgrade

`./install.sh --check` first: read-only, it names the route it detects, compares the recorded
version and the installed engine against the checkout, and prints the exact re-run. Then
re-running `install.sh` is the upgrade. The engine directory is replaced wholesale — but first it
is compared against the `.installed-engine` manifest, and anything you patched is named and kept
at `engine.prev`. The corpus is never overwritten; commands are treated individually against the
`.installed-commands` manifest:

| State of the installed command | Action |
|---|---|
| absent | install |
| identical to what we would write | already current |
| matches the manifest — ours, untouched | update |
| differs from the manifest, or has no entry | **skip, and say so** |

A skipped command's shipped version is saved to `raememberit/shipped/<name>` with a runnable
`diff` printed, so the warning can be acted on rather than merely noted. `--force-commands`
takes the shipped version anyway, and is deliberately **separate** from `--force`: topping up a
scaffold should never be a reason to discard someone's command text.

Without the manifest the only safe policy would be "never update", stranding every adopter on
whatever version they first installed. This is the same reason a package manager treats config
files this way.

**Anything worth keeping across an upgrade belongs in `settings.json` `env`, not in a script.**

## Stage 10 — Exit

```bash
./uninstall.sh          # removes tooling, KEEPS your memories
./uninstall.sh --purge  # also deletes them, after you type DELETE
```

It removes only its own hooks, commands, permission rules, env entries and the plugin directory
it placed — asserted by test, not merely promised, on all three routes. Your own hooks, rules and settings are untouched, and the memories remain plain
markdown that stays readable with this tool gone.

A tool nobody can back out of cleanly is a tool nobody should adopt.

---

## The lifecycle of a single memory

```
  a correction, or a fact that cost effort
        │
        ▼
  /learn ──▶ find-similar.py ──▶ (near-duplicate? update the existing file instead)
        │
        ▼
  mem-write.sh  ── schema gate ──▶ <corpus>/<type>/<slug>.md
        │
        ▼
  rebuild-index.sh ──▶ feedback/  ──▶ MEMORY.md          (always-on, injected every context)
                   └─▶ project/   ──▶ MEMORY-CATALOG.md  (on-demand, reached via /recall)
                       reference/
        │
        ▼
  read back by /recall ──▶ acted on ──▶ recurs twice ──▶ /skill-mine promotes it to a skill
        │
        ▼
  superseded ──▶ archive/   (excluded from every index, deliberately)
```

`project/` **is not a status signal.** Finished work stays there unless you move it, so the
directory name says nothing about whether something is still live — read the body for
SHIPPED / DONE / merged / closed before treating a hit as current.

## State the kit keeps outside the corpus

Every stage above is stateless except these. When something misbehaves, this is the list to
inspect first.

| State | Written by | Cleared by | Governs |
|---|---|---|---|
| `${TMPDIR}/raememberit-injected-<sid>` | `inject-memory.sh` | `rearm-inject.sh` | one injection per context window |
| `<corpus>/.last-sweep` | `/skill-mine` | never (advanced) | the sweep delta and the session-start nag |
| `raememberit/.installed-commands` | `install.sh` | `uninstall.sh` | the four-state upgrade policy for commands |
| `skills/raememberit/.raememberit-placed` | `install.sh --as-plugin` | replacing the directory | the same policy for the plugin directory: untouched is updated, edited is skipped |
| `raememberit/.installed-engine` | `install.sh` | `uninstall.sh` | the engine as written, so an upgrade can name what you patched |
| `raememberit/engine.prev` | `install.sh`, only when the engine differed from its record | the next clean upgrade | the previous engine, kept so a local patch can be re-applied or upstreamed |
| `raememberit/.config` | `install.sh` | `uninstall.sh` | the remembered addressee and optional files, plus `version=` and `schema=` — what `--check` and a future migration read |
| `<corpus>/.seeded-starters` | `install.sh` | never | which starter rules this corpus ever received, so a `--force` top-up never re-adds one you deleted |
| `raememberit/shipped/<name>` | `install.sh` on a skip | you | recovering a shipped command you chose not to take |
| `$CLAUDE_PLUGIN_DATA/bin/mem-write.sh` | `place-shim.sh` | plugin removal | a version-free path for the permission rule |
| `<corpus>/.domain-index` | `rebuild-index.sh` | next rebuild | domain → memory rows, read by the prompt-time context router |
| `<corpus>/.index-status` | `rebuild-index.sh` | next rebuild | the always-on budget verdict, `OK`/`OVER`, surfaced by the tripwire |
| `<corpus>/.index-rebuild.log` | `rebuild-index-hook.sh` | next rebuild | the rebuild's own output, which used to go to `/dev/null` |
| `starter/baseline.json` | the maintainers | — | the frozen retrieval score CI holds the kit to |

## Invariants that hold at every stage

1. **Markdown is the source of truth.** Every index is derived and regenerable; the corpus
   survives a `cp -r`. No database, no vector store, no daemon.
2. **Indexes are never hand-edited.** Edit frontmatter and re-run `rebuild-index.sh`.
3. **Writes go through `mem-write.sh`.** Not the Write tool — it is refused inside `.claude`,
   and it could not enforce the schema anyway.
4. **Every path resolves through `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`** (or
   `${CLAUDE_PLUGIN_ROOT}` for code). `CLAUDE_CONFIG_DIR` relocates the config but does **not**
   change `$HOME`, so a hardcoded `~/.claude` keeps writing the default corpus even when the
   session is pointed elsewhere.
5. **One mechanism, one description.** `hooks.json` and the README's hook table are generated
   from `settings.fragment.json`, and `tools/test-docs.sh` fails when they drift — including
   the assertion count in the README.
6. **A knob, not an edit.** `install.sh` replaces the whole engine directory; anything
   customized in a script is kept aside at `engine.prev` and named, not carried forward, and
   anything in `settings.json` `env` survives untouched.
7. **Scanning zero files is an error, not a pass.** The sanitization gate carries no file
   exclusions — an excluded file is a blind spot, and a gate with blind spots is decoration.

## Where each feature lives

| Stage | Feature | Path |
|---|---|---|
| 0 | plugin manifest, generated hooks | `plugin/.claude-plugin/plugin.json`, `plugin/hooks/hooks.json` |
| 0–1 | hook wiring, single source | `engine/settings.fragment.json` |
| 1 | installer, uninstaller | `install.sh`, `uninstall.sh` |
| 1 | empty corpus layout, starter rules | `scaffold/`, `starter/`, `starter/optional/` |
| 2–7 | the eight hooks | `engine/hooks/` |
| 3 | index generator | `engine/rebuild-index.sh` |
| 4–8 | the five commands | `protocol/*.md.tmpl` |
| 5 | write path, duplicate detection | `engine/mem-write.sh`, `engine/find-similar.py` |
| 8 | eval harness, frozen baseline | `engine/eval/run_eval.py`, `starter/baseline.json` |
| — | sanitization gate, doc-consistency check | `tools/sanitize-scan.sh`, `tools/test-docs.sh` |
