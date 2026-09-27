<!-- raememberit — paste into your CLAUDE.md, or keep it as a separate file and reference it.
     This is a FRAGMENT. It is not a replacement for your own instructions. -->

## Memory

A durable memory corpus sits **beside** your Claude Code config directory — its path is published
as `$RAEMEMBERIT_MEMORY_DIR`. It has two tiers, because context injected into every prompt is the
scarcest resource here:

- **Always-on** — `feedback/` standing rules, injected automatically into every context.
- **On-demand** — `project/`, `reference/` and `interactions/`, pulled in by `/recall` only when a
  task touches their subject.

It is a sibling of the config directory rather than inside it for a measured reason: Claude Code
treats any path inside a `.claude` directory as a **sensitive file** needing per-file approval, and
an explicit allow rule does not override that. A corpus in there would prompt on every single
memory write.

### Two commands that should fire without being asked

- **`/recall <topic>` before investigating anything cold** — a repo, a ticket, an error string, a
  tool. Assume a relevant memory exists until the catalog says otherwise.
- **`/learn` the moment you are corrected**, or a non-obvious fact costs real effort. Immediately,
  mid-task — not at the end of the session, by which point you remember *that* you were corrected
  and not the sentence that corrected you.

### What the hooks do to your session

| When | What |
|---|---|
| Every new context | the always-on index is injected once, then suppressed until the context resets |
| Session start | if enough new interaction logs have accumulated, a pattern sweep is *offered* — never run automatically |
| Before compaction | a reminder to capture durable memory first |
| Session end | both indexes are regenerated from frontmatter |
| Session end, no interaction log today | a **reminder**. Set `RAEMEMBERIT_REQUIRE_LOG=strict` to make it block instead, or `off` to silence it |

### One thing that surprises everyone once

Claude Code refuses to write outside its working directory without permission, so a `/learn` can
appear to do nothing while it asks. The installer already adds an allow rule for the corpus, so this
should not bite — but if it does, the rule to add is `Edit(<corpus path>/**)`, and the corpus path
is in `$RAEMEMBERIT_MEMORY_DIR`.

### Never hand-edit the indexes

`memory/MEMORY.md` and `memory/MEMORY-CATALOG.md` are generated from each memory's frontmatter.
Edit the memory, then:

```bash
bash raememberit/engine/rebuild-index.sh
```
