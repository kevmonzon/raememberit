---
name: dont-restate-existing-test-coverage
description: Do not add tests that re-assert what an existing test already covers — the urge to make a point "visible in one place" is a documentation need, not a test need.
metadata:
  type: feedback
---

When adding tests, check whether each case asserts something **no existing test asserts**. If the
fact is already covered, do not add a second test restating it for emphasis, grouping, or
readability.

**Why:** on one pull request a reviewer flagged the same mistake **three times in a row**, with
escalating severity, while the production code had been approved from the start:

1. A private helper was tested indirectly through a public entry point, with five layers of mock
   scaffolding per case, instead of moving the helper somewhere it could be public. A repository
   rule saying "private behaviour is guaranteed through public behaviour" means *make it public if
   it deserves direct testing* — not *contort the test around it*. **Move the code, not the test.**
2. After extracting the helper and its boundary matrix into a new test file, three cases were kept
   in the original file "to prove the wiring". All three were duplicates — two of the new table,
   one **byte-identical** to a test that predated the change. The correct diff for that file was
   always *no diff*.
3. A further test asserted four adjacent-day pairs "to make the boundary argument visible". All
   four dates were already rows in the parametrized table. Zero new coverage.

Every redundant test is a line a reviewer must read and someone must later maintain, and it makes
the real coverage harder to find. Three review rounds went on this instead of the fix.

**How to apply:**
- Before adding a test, grep for the target value, date or input. If it already appears in an
  assertion, do not add it again.
- Before defending a test as proving something unique, **verify that claim** against the existing
  tests in the file. Uniqueness was asserted twice here and disproved by a two-line grep.
- When a case's *rationale* needs to be visible, put it in a docstring or a descriptive parametrize
  id — never in a duplicate assertion.
- Read reviewer severity as signal: a repeated note that escalates means the point is not landing.

Related: [[prove-regression-test-fails-without-the-fix]] (a test that cannot fail is the same
defect from the other side) and [[lead-with-consequence-not-mechanism]] (when the point is
*rationale*, prose is the right medium — not another assertion).
