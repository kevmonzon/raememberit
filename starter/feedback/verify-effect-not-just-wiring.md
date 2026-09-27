---
name: verify-effect-not-just-wiring
description: When verifying a feature, exercise the real runtime effect — not just that settings or state propagated. A green plumbing check will ship a broken feature.
metadata:
  type: feedback
---

When claiming a feature "works", verify the **actual effect**, not just that the plumbing moved.

**Why:** a UI control for an audio feature was reported working after only confirming that the
control's *value* synced between two devices. Exercising the real path — playing audio and
measuring the affected channel's level — showed the setting propagated but had **no audible
effect**, and exposed a further bug: a mute/unmute cycle left the channel permanently silent,
because a volume message the unmute path never re-sent stayed latched. A settings-sync green check
would have shipped a broken feature as done.

**How to apply:**
- For anything with a side effect — audio, UI, network, database — drive the end-to-end path and
  measure the *outcome*: sound level, pixels, the request, the row. Not that a variable, a
  `localStorage` key or a DOM attribute changed.
- Watch for early returns that no-op the effect under test conditions. A function that bails when
  a resource is not ready proves nothing when tested without that resource.
- A temporary in-process probe, removed afterwards, is a fair way to measure otherwise-hidden state.
- Treat "does this actually work?" as a request to test the *effect*, and say explicitly what was
  measured. See [[verification-tail-masks-failure]], where the plumbing actively fakes the outcome.
