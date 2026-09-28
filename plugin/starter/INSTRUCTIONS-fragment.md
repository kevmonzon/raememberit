<!-- raememberit — paste into your CLAUDE.md, or keep it as a separate file and reference it.
     This is a FRAGMENT. It is not a replacement for your own instructions. -->

## Memory

A durable memory corpus lives in this Claude Code config directory, under `memory/` — so the whole
directory stays one portable unit. Its path is also published as `$RAEMEMBERIT_MEMORY_DIR`. It has
two tiers, because context injected into every prompt is the scarcest resource here:

- **Always-on** — `feedback/` standing rules that declare `metadata.scope: global`, injected once
  per context window. An absent `scope:` counts as `global`.
- **On-demand** — `domain`-scoped feedback, plus `project/`, `reference/`, `archive/` and
  `interactions/`, pulled in by `/recall` only when a task touches their subject.

A `feedback` memory therefore **chooses** which tier it lands in. The test: *would I want this in
front of me before I know what the task is?* Consent and epistemic rules usually pass; craft advice
about one repo, language or tool usually does not. Absence is the safe default, not a decision —
a tier that only ever grows stops being delivered at all, silently, past a size ceiling.

### Writing memories: use the helper, not the Write tool

```bash
<config>/raememberit/engine/mem-write.sh <feedback|project|reference> <slug> <<'EOF'
... full markdown ...
EOF
```

Claude Code treats any path inside a `.claude` directory as a **sensitive file**, and the Edit and
Write tools refuse it per file — an allow rule does not override that. Bash is not gated, so the
helper is the write path, and the installer allow-lists it. It also validates the schema and runs the
duplicate gate, so a bad memory is refused rather than quietly stored.

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

If you try to write a memory with the Write or Edit tool it will be refused as a sensitive file, and
no permission rule will fix that. That is not a broken install — it is why `mem-write.sh` exists. The
installer allow-lists the helper, so the commands do the right thing already.

### Never hand-edit the indexes

`memory/MEMORY.md` and `memory/MEMORY-CATALOG.md` are generated from each memory's frontmatter.
Edit the memory, then:

```bash
bash raememberit/engine/rebuild-index.sh
```
