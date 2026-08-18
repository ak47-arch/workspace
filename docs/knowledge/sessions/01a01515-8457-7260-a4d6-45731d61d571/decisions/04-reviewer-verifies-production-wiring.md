## Decision: Reviewer must verify production wiring — not just green tests

**Status**: accepted
**Date**: 2026-08-19 04:20
**Task**: multi-repo-delivery-bookkeeping-prs
**Project**: software-factory
**Session**: sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl

### Context

The implementer delivered PR #12 with **219 tests passing across all four suites**. The adversarial review still returned REQUEST_CHANGES with five blocking findings (B-1…B-5) and J2/J3 conformance items. The root cause: the unit tests set the wiring seams themselves — `BK_MANIFEST`, `FACTORY_REPOS`, `BOOKKEEPING_PR` are all exported inside the tests — so the production code path was never exercised without them.

### Problem

Green tests are necessary but not sufficient. If the tests configure the seams they claim to prove (e.g. `factory-run.sh` only raises a bookkeeping PR when a caller sets `BK_MANIFEST`, and the test — not any live invocation — sets it), production wiring gaps are invisible to the suite but fatal at runtime.

### Alternatives

- Rely on CI test runs alone — rejected: the CI runner runs the same seam-setting tests, so it would also pass while deliver nothing live.
- Manual operator smoke — required anyway at UAT, but happens too late (after merge).

### Decision

Keep the adversarial review gate as the binding correctness authority, and require the reviewer to trace env seams to a live caller (grep for who sets a seam outside the test files). Add a **production-wiring smoke test** that runs the scripts with **no** factory env seams exported, so the "seam inert" class of bug is caught by the suite/CI rather than only by the reviewer.

### Rationale

The review caught what the suite masked — exactly the value of a judgment check (`J2` PRD-decision conformance, `J3` fail-loud) over deterministic ones. A wiring smoke test closes the loop so the gap is prevented at build time.

### Consequences

- Revision 1 fixed all five blockers in scope (229 tests, re-review APPROVE).
- Follow-up hardening task: add the seam-free wiring smoke test.
- The invariant is now asserted at the correct point (delivery-time for Shape A, loop-end re-assert of the A/B XOR).

### Revision triggers

- If a production-wiring smoke test is added and passes for N consecutive tasks without the reviewer needing to raise the seam-inert class again.
