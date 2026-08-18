# Decision: Shape A delivery-invariant assert point must move past bookkeeping-PR creation

**Status**: proposed (raised by code review)
**Date**: 2026-08-18
**Task**: multi-repo-delivery-bookkeeping-prs
**Review session**: 745d22cb-1a68-49b2-b859-07173257e29e

## Context
The delivery invariant is the A/B XOR: `(root code PR exists AND no bookkeeping
PR) XOR (no root code PR AND exactly one bookkeeping PR)`. The PRD says assert it
"after every delivery" and "after loop end".

`assert_delivery_invariant` is currently called at the end of `deliver_repo_set`
in `bin/implementer-run.sh`. At that point the implementer has only raised the N
code PRs; the Shape A bookkeeping PR is raised **later** by `factory-run.sh`
`finish_bookkeeping()` (loop end). `BOOKKEEPING_PR` is therefore always empty when
the implementer asserts, so for any Shape A task (root not touched) both terms are
false → the invariant is falsely violated → `fail_run`. A legitimate multi-app-repo
delivery dies.

## Decision
Defer the Shape A side of the invariant until the bookkeeping PR exists:
- In `implementer-run.sh` assert only what is true at delivery time: if the root is
  in the set (Shape B), there must be a root code PR and no bookkeeping PR; if the
  root is NOT in the set (Shape A), do not require a bookkeeping PR yet (it is
  pending).
- Re-assert the full A/B XOR in `factory-run.sh` after `finish_bookkeeping()` (the
  "loop end" assertion the PRD already calls for), where `BK_PR`/`BOOKKEEPING_PR`
  is populated — or pass the bookkeeping PR back so the implementer-side assert can
  run once complete.

## Consequences
Fixes the false-fail (review finding B-1). The invariant's "no third shape" safety
is preserved but evaluated at a point where all evidence exists. The loop-end assert
is currently missing (factory-run never re-asserts) — add it.
