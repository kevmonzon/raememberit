# Memory

A durable, portable memory corpus. Plain markdown; no database, no daemon. It lives inside the
Claude Code config directory, so a `cp -r` of that directory takes your memory with it.

**Write into it with `raememberit/engine/mem-write.sh`, not the Write tool.** Claude Code treats any
path inside a `.claude` directory as a sensitive file the Edit/Write tools refuse per file, and an
allow rule does not override it. Bash is not gated, which is what the helper uses — and the helper
validates the schema on the way in.

## Two tiers, and why

Context injected into every prompt is the scarcest resource here, so the corpus is split:

- **Always-on** — standing behavioural rules, obeyed regardless of topic.
- **On-demand** — pointers consulted only when a task touches their subject.

Putting project and reference memories in the always-on tier is the mistake this structure
exists to prevent.

| Path | Tier | Holds |
|---|---|---|
| `MEMORY.md` | **always-on** | generated index: profile + every `feedback/` rule + the latest interaction logs |
| `MEMORY-CATALOG.md` | on-demand | generated index of every `project/` + `reference/` memory |
| `user_profile.md` | always-on | who you are — role, stack, preferences |
| `feedback/` | always-on | behavioural guidance: how the assistant should work |
| `project/` | on-demand | project state not derivable from code or git history |
| `reference/` | on-demand | pointers to external systems — dashboards, tickets, commands |
| `interactions/` | on-demand | per-session logs, `YYYY-MM-DD-HH-MM-topic.md` |
| `archive/` | excluded | superseded material, deliberately not indexed |
| `artifacts/` | excluded | generated deliverables referenced by memories |
| `eval/` | excluded | the retrieval eval harness and its scored baselines |

⚠ **`project/` is not a status signal.** Finished work stays there unless you move it, so the
directory name says nothing about whether something is still live. Read the body for
SHIPPED / DONE / merged / closed before treating a hit as current. In the corpus this kit was
extracted from, **62% of `project/` memories described work that had already shipped.**

## Memory format

```markdown
---
name: short-kebab-case-slug
description: one line, used to decide relevance during retrieval
metadata:
  type: user | feedback | project | reference
---

The fact. For feedback and project memories, follow with **Why:** and **How to apply:**.
Link related memories with [[their-name]].
```

## Keeping the indexes fresh

Both are generated from frontmatter — **never hand-edit them**:

```bash
bash engine/rebuild-index.sh
```

It prints each tier's entry count and byte size, so a regression in the always-on surface is
visible immediately. A `SessionEnd` hook runs it automatically.

Counts are deliberately not written into prose anywhere in this corpus. They drift within
days. Run the script.
