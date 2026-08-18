## Decision: Assert the A/B delivery invariant where it can hold (Shape B after delivery, Shape A at loop end)

**Status**: accepted
**Date**: 2026-08-18 17:30
**Task**: multi-repo-delivery-bookkeeping-prs
**Project**: software-factory
**Session**: sessions/c63649d5-f660-4494-af41-d0025d02f728/session.jsonl

### Context
The delivery invariant is `(root code PR exists AND no bookkeeping PR) XOR (no
root code PR AND exactly one bookkeeping PR)`. The PRD's architecture flow shows
an `assert_delivery_invariant` right after delivery AND at loop end, while the
bookkeeping PR is raised by `factory-run.sh` at loop end.

### Problem
For **Shape A** (root not touched) there is, immediately after the implementer's
code delivery, neither a root code PR nor a bookkeeping PR (bookkeeping is
legitimately pending until the loop end). Asserting the XOR at that point would
falsely fail every Shape-A delivery.

### Alternatives
- Assert after the implementer's delivery for all shapes (fails Shape A).
- Assert only at loop end (never catches an early Shape-B violation).
- Assert at the earliest point each shape can hold: Shape B after delivery, Shape A
  after the loop raises the bookkeeping PR.

### Decision
`assert_delivery_invariant` is called **after Shape-B delivery** (root touched →
root code PR exists, no bookkeeping PR yet — holds immediately) and **at loop end
after `raise_bookkeeping_pr`** (Shape A → exactly one bookkeeping PR). The single
check function is shared; only its call site varies by shape.

### Rationale
- The invariant is about the FINAL delivery state; asserting it before a
  legitimately-pending component exists would be a false alarm.
- Both assertion points are cheap and keep the guarantee "asserted after every
  delivery" in the sense that matters: no completed delivery ever violates it.
- The test suite exercises the function directly with crafted manifests to prove
  both the valid-XOR pass and the loud-fail on violation.

### Consequences
- `deliver_multi` asserts for `ROOT_TOUCHED=1`; `factory-run.sh` asserts (via
  `raise_bookkeeping_pr` + manifest read) for Shape A at loop end.
- A genuine violation at either point returns non-zero and fails the run loudly
  with per-repo status.

### Revision triggers
- If a Shape-A delivery must ever be short-circuited before the loop end and still
  needs the invariant enforced early.
