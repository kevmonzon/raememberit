---
name: dont-conclude-impossible-prematurely
description: Do not declare something impossible from absence of evidence — "I did not find it" is not "I proved it cannot be done". But do make honest diminishing-returns calls, and name which mode you are in.
metadata:
  type: feedback
---

On hard investigative work — reverse engineering, an elusive bug, an undocumented format — **do
not conclude "impossible" from absence of evidence.**

**Why:** during one reverse-engineering effort the obvious code paths were traced, no software
decoder was found, and the conclusion "decoded in hardware, not software-recoverable" was written
into the delivered report as a verdict. One more trace found the actual software decoder, and real
audio was decoded out of what had been called impossible. The conclusion was not a proof; it was
"I did not find it in the parts I looked at", dressed up as "it cannot be done".

**How to apply:**
- Distinguish *"I proved it cannot be done"* from *"I have not found it yet"* — and say which it
  actually is. The second is not a verdict.
- Enumerate what is **unchecked** before calling anything impossible.
- "Not yet, and here is the next concrete lever" beats closing a door that is not closed.
- Correct delivered artifacts promptly when a conclusion is overturned.

**The balancing half — these are not in conflict, hold both.** Across roughly sixteen rounds of
pushing on one problem:
- Keep going while each round produces a **new concrete lever**: a new function to trace, a new
  decode to try, a new crib. That is real progress.
- When several rounds in a row **grind the same seam with no new lever**, stop and say so, then
  offer a **pivot** — a different sub-goal that still serves the objective. Offering a pivot is not
  concluding impossible; it is honest routing.
- Always name which mode you are in: "here is the next lever" (keep going) versus "I am not
  converging; here are the real routes, pick one" (honest fork). Do not dress thrashing up as
  momentum.

Stating a **proven wall for the attacks tried, plus the one named route left**, is the correct
shape of a negative result. "Impossible" is not.

Related: [[read-full-build-output-not-just-the-tail]] — the most common reason something looks
impossible is that the answer was printed somewhere nobody read.
