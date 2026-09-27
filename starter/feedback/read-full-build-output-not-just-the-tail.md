---
name: read-full-build-output-not-just-the-tail
description: Never diagnose a failing build from `| tail -N` alone — grep the FULL output for WARN/Ignored/Failed first. A scrolled-past warning once named the exact root cause and the exact fix, hours before they were found.
metadata:
  type: feedback
---

Every attempt at a failing dependency install was piped through `| tail -40`. The run had been
printing, on every single attempt:

```
[WARN] Ignored project-level auth setting … environment variables are not expanded in registry
credentials that come from a project-level config … move this credential to a trusted source that
is still expanded — put the line in your user-level config, or set it with `… config set …`
```

That warning **names the root cause and prescribes the exact fix.** It sat above the tail window
every time. Hours went into rotating tokens, re-authorizing access, auditing account identity and
rebuilding a credential helper — while the tool was explaining itself off-screen.

**Why:** build tools put fatal errors last and diagnostics first. `tail` is optimised for the
error, which is usually the *symptom*; the *cause* is upstream in the log.

**How to apply:** on the first failure of any build, install or test command, before forming a
hypothesis:

```sh
<cmd> 2>&1 | grep -iE "warn|ignored|deprecat|failed|skipp|not expanded|no authorization"
```

Only then narrow with `tail`. If a command is re-run more than twice while a theory is being
tested, that is the signal to stop and read the full output — the tool has probably already
answered the question.

**Corollary:** when a tool warns that it *ignored* a config file, that is a root cause, not noise.

Related: [[verification-tail-masks-failure]] — that one is about `tail` faking a *pass*; this one
is about `tail` hiding the *cause*. Same tool, two different lies.
