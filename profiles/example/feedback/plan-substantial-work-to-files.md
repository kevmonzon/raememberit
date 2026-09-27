---
name: plan-substantial-work-to-files
description: For substantial build or design work, persist the plan to dated, versioned files before writing code — and have a different model review it adversarially.
metadata:
  type: feedback
---

For substantial build or design work, run a planning phase that is **persisted to files** before
any implementation:

1. **Research first, and write it down** — into a dated markdown dossier in the working directory.
   Keep it updated live as the discussion evolves, not reconstructed afterwards.
2. **The plan is a durable file, not a chat message.** Something that can be referred back to
   weeks later.
3. **Adversarial review by a different model.** A second model catches gaps the first is
   systematically blind to. Fold the findings back in.
4. **Version the plan** — v1 → v2 → v3, each with a changelog saying what changed and why. Keep
   prior versions as the rationale record rather than overwriting them.
5. **Clarify genuinely ambiguous forks before finalizing**, and only those.

**Why:** a plan treated as a long-lived governance document produces a specification an
implementing agent can execute cold. One treated as scaffolding does not survive the first week.

**How to apply:** default to this for any multi-component build.

---

*This rule ships in the `example` profile rather than the starter set on purpose.* It is a
**working preference**, not an engineering truth — reasonable people run projects differently, so
it belongs in a profile a person opts into. That distinction is the line the starter set is
selected on.
