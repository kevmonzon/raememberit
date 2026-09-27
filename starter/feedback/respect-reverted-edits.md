---
name: respect-reverted-edits
description: When the user reverts or overrides an edit, do not silently re-apply it. Re-check current state, name what is missing relative to the prior change, and let the user decide.
metadata:
  type: feedback
---

When the user reverts or overrides an edit — explicitly ("I had to override some files"), or
implicitly (the file has changed back) — **do not auto-re-apply on the next pass.**

**Why:** a revert signals reasons that may not be visible: scope discipline, branch hygiene,
in-flight work elsewhere, an alternative already planned. Stomping back on top of it is worse than
leaving the improvement out.

**How to apply:**
- On a re-check, read the current state fresh. Do not assume prior edits are still present.
- If a prior improvement is gone, **say so plainly** — "the unhandled-exception leak is back" — and
  do **not** re-apply it.
- Offer to re-apply, or to defer, and let the user choose.
- If asked why it was not re-applied, this rule is the reason.

Observed when a missed exception leak had been patched, the user reverted it because they needed to
override some files temporarily, and then asked for a re-check. The correct response was to
re-verify, surface the still-existing gap, and wait.

Related: [[documented-invariant-is-a-claim]] — read the current state before acting on a
remembered one. A revert is the file disagreeing with your memory of it, and the file wins.
