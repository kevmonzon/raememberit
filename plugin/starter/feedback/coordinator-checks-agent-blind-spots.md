---
name: coordinator-checks-agent-blind-spots
description: When fanning out narrowly-scoped subagents, the coordinator's job is not reviewing their code but checking each locally-correct result against the whole-system context the agent structurally could not see.
metadata:
  type: feedback
---

When orchestrating parallel, narrowly-scoped subagents, expect each to produce work that is
**locally correct and globally wrong at exactly one edge** — the edge that depends on context
outside its brief.

**Why:** on one multi-agent build this held **four times out of four**:

- A latency-watchdog agent satisfied "no added latency" by buffering — which would have turned
  time-to-*first* output into time-to-*complete* output, silently destroying the budget. The
  constraint that made this wrong lived in a different milestone's risk list, invisible to it.
- An auth agent added the guard exactly where the plan said, but the identifier it guarded was
  allocated one file earlier, and two sibling endpoints had no auth at all.
- A config agent wired live reload for model swaps, not knowing that the object being swapped *was*
  the conversation memory — so a "live" swap would have wiped every open conversation.
- A correct new input path shipped while a **pre-existing** second pipeline kept streaming.

Each agent did good work **and flagged its own trade-off.** The buffering error was caught only
because the brief required surfacing trade-offs rather than resolving them silently.

**How to apply:**
- Brief subagents to **surface trade-offs and assumptions, not resolve them silently.** That
  self-report is what lets the coordinator catch the global-edge error.
- After each result ask: *what does this depend on that the agent could not see?* — a later
  milestone's risk, a sibling endpoint, a shared-by-reference object, an old path the new one does
  not remove.
- **A new correct path does not make an old path stop existing.** Check for the duplicate.
- Give agents strictly disjoint file ownership so their blind spots cannot collide.

Relevant only where multi-agent orchestration is actually in use.

Related: [[verify-effect-not-just-wiring]] — "it works" from an agent means it works inside that
agent's brief. Check the effect at the seam it could not see.
