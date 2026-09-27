---
name: verification-tail-masks-failure
description: Never end a verification pipeline with `| tail` before `&&` — the `&&` reads tail's exit code, not the command's, so a failing build prints "OK". Capture the real exit code.
metadata:
  type: feedback
---

When verifying that a command succeeded, **do not pipe it into `tail` or `head` and then
`&& echo "OK"`.** The `&&` tests the exit status of the *last stage of the pipeline*, which almost
always succeeds — so a failing build, test or compile prints a reassuring "OK" over a red result.

**Why:** a build verification was written as `go build ./... 2>&1 | tail -5 && echo "build OK"`. It
printed "build OK" while the build was **failing** — the toolchain version did not match the one
the repository pinned. Re-running with the real exit code captured showed the failure immediately.
A false green in a verification step is worse than no check at all: it launders a broken state as
confirmed.

**How to apply:**
- Capture the command's **own** exit status: `cmd; echo "exit=$?"`, or `set -o pipefail` before a
  piped check, or run it bare and inspect `$?`.
- Treat any "verified working" claim that rode on `| tail && echo` as **unverified** until rechecked.
- Same family as [[verify-effect-not-just-wiring]]: prove the outcome, not the plumbing. Here the
  plumbing actively fakes the outcome.

Related: [[shell-dialect-traps]] — the exit-code trap has a whole family of siblings in whichever
shell is actually running your commands.
