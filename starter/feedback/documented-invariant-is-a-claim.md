---
name: documented-invariant-is-a-claim
description: A documented invariant — in project instructions, a README, a comment or a memory, even one marked "verified" — is a claim, not a fact. When a quiet symptom touches it, measure the behaviour live before reasoning from it.
metadata:
  type: feedback
---

When a bug's symptom is quiet and the failing path is guarded by a documented rule, **measure the
rule before reasoning from it.**

**Why:** a media player never advanced its queue for one file type. The repository's own
instructions declared that the library left a `paused` flag false at natural end, and made a
`!paused` guard "mandatory" — marked *verified in-browser*. Measured live, the real values were
`paused: true, ended: true, position == duration`. The guard was vetoing the very event it existed
to catch, and the bug survived three rounds of work because the document was trusted. The fix
anchored on the clock instead, and the document was rewritten around the measurement.

Doc-trust is how quiet bugs live for months. "Verified" records that someone checked once, under
conditions you cannot see.

**How to apply:** when a documented invariant sits on the failing path, write a throwaway probe and
log the actual values first. If the document is wrong, fix the document in the same change.

**This applies to a memory corpus too, and has bitten one.** A memory describing a hook guard was
contradicted by the settings file it described — and the claim then flipped **three times across
three audits**, because each audit reasoned from the previous audit's prose instead of re-reading
the file. A memory may record a **mechanism**; only the file records the **current value**.

Related: [[verify-effect-not-just-wiring]] (measure the outcome, not the description of it) and
[[dont-conclude-impossible-prematurely]] ("the doc says so" and "I did not find it" are the same
error wearing different clothes).
