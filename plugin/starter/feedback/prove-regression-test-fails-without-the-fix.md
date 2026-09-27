---
name: prove-regression-test-fails-without-the-fix
description: Before calling a test a regression test, stash the fix and watch it fail — a test that passes without the fix proves nothing.
metadata:
  type: feedback
---

A regression test that still passes with the fix reverted is decoration, not evidence. Demonstrate
the red state before reporting the green one:

```bash
git stash push -m "TEMP: verify new test fails without fix" -- <implementation file only>
<run just the new tests>            # expect FAIL — capture the assertion text
git stash pop
git stash list                      # confirm pre-existing stashes survived
```

Stash **only the implementation file**, never the test file, or you prove nothing. Report the
actual failing assertion, not the sentence "it fails without the fix".

**Why:** it is easy to write a test that passes for the wrong reason — wrong boundary, wrong
fixture, an assertion that never binds. Stash-and-fail is the only cheap proof that the test is
wired to the behaviour it claims to guard. It also pins the exact boundary, which is often not the
number the reporter guessed: on one review finding the reviewer predicted a cap at 20 items, and
the stash-and-fail run showed the true boundary was **19**, because null entries returned early
and never consumed budget.

**How to apply:** run it for every fix made in response to a review finding, and quote the failing
assertion alongside the fix summary. Pair it with a second test guarding the *other* direction —
that the fix did not loosen an existing bound. Such a test passes both before and after, which is
correct, so say so explicitly rather than presenting it as regression proof.

Related: [[dont-restate-existing-test-coverage]] — that rule stops you adding a test nothing needs;
this one stops you trusting a test that guards nothing. Run both checks on the same diff.
