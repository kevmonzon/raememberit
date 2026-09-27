---
name: lead-with-consequence-not-mechanism
description: Asked to "explain in one simple sentence", answer with what breaks if the change is absent — not with the mechanism, even when the mechanism is accurate.
metadata:
  type: feedback
---

"Explain in one simple sentence" was asked **three times in a row** about three one-line
infrastructure changes. Each first answer was technically correct and pitched too high:

| First answer (rejected) | What actually landed |
|---|---|
| "Attaches the shared egress security group to the app nodegroup." | "It lets that service's nodes reach the authentication services — without it, the transformer would sit on those nodes unable to reach anything." |
| "Exports the role ARN across state boundaries." | "It publishes the role ID so the key config in another folder can refer to it — without it, that config has no way to name this role." |
| "Adds a third node selector term to the daemonset." | "It tells the daemonset to run on the new nodes too — until now it only ran on two other groups', so the new pods had nothing to talk to." |

**Why:** the mechanism restates the diff in jargon, and the diff is already readable. What cannot
be read off the line is the *consequence* — and that is what is needed to defend the change in
review or explain it to a teammate.

**How to apply:**
- Lead with what breaks if the line is absent, or what becomes possible because it is present.
- Name the concrete counterparties rather than abstractions — the specific service, the specific
  config — not "auth services" or "remote state".
- Put the mechanism in a short second sentence only when it is load-bearing.
- One sentence means one sentence. Do not restate the line that was just quoted back at you.

Related: [[dont-restate-existing-test-coverage]] — both are the same discipline: do not repeat
something already on the page to make it feel more established.
