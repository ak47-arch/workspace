## Decision: Split the A/B delivery invariant into a delivery-time assert and a loop-end assert

**Status**: accepted
**Date**: 2026-08-18
**Task**: [multi-repo-delivery-bookkeeping-prs](../../../../tasks/multi-repo-delivery-bookkeeping-prs.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Accepted: two-stage assertion with the run manifest as the single source of truth.

### Context
The delivery invariant (review decision 01 + blocking finding B-1) is the A/B XOR: a touched root gets a root code PR and NO separate bookkeeping PR; an untouched root gets NO root code PR and exactly one bookkeeping PR. `assert_delivery_invariant` was asserted inside `deliver_repo_set` immediately after the implementer raised the N code PRs — at which point the Shape A bookkeeping PR (raised later by factory-run at loop end) does not exist, so `BOOKKEEPING_PR` is always empty and every legitimate Shape A multi-app delivery invoked the "neither → violation" branch and `fail_run`.

### Problem
A single assertion point cannot see both sides of the XOR: the implementer sees the code PRs but not the pending bookkeeping PR; factory-run sees the bookkeeping PR but not the per-repo code-PR map at loop end.

### Alternatives
1. Assert the full XOR only in factory-run after `finish_bookkeeping`, dropping the implementer-side assert entirely.
2. Have the implementer pass its per-repo PR map to factory-run so factory-run can assert post-bookkeeping.
3. **Accept the review decision: assert only what is true at each stage, from a single durable source (the run manifest).** Implementer asserts delivery-time semantics; factory-run re-asserts the full XOR at loop end reading `root_code_pr` vs `bookkeeping_pr` from the manifest.

### Decision
**Accepted: two-stage assertion with the run manifest as the single source of truth.**
**Summary**: ## Decision: Split the A/B delivery invariant into a delivery-time assert and a loop-end assert Status: accepted Date: 2026-08-18 Task: multi-repo-delivery-bookkeeping-pr
- `insert in implementer-run.sh` `assert_delivery_invariant` (delivery-time): Shape B (root in set) → require a root code PR and no bookkeeping PR; **Shape A (root not in set) → hold unconditionally** (bookkeeping PR is pending at loop end). Removes the false-fail.
- `writer in factory-run.sh` `assert_loop_end_invariant <manifest>`: full A/B XOR on `root_code_pr` vs `bookkeeping_pr` from the run manifest. Run after `finish_bookkeeping` in both headless and non-headless chain end. Fail-loud (non-zero) on "both" or "neither" — so a Shape A task whose bookkeeping PR silently failed is caught.
- `finish_bookkeeping` skips raising a separate bookkeeping PR when `root_code_pr` is set (Shape B): the root PR already carries the bookkeeping commits, so raising one would violate the XOR.
- The bookkeeping PR number is mirrored back into the manifest (`set_manifest_bookkeeping_pr`) immediately after `gh pr create`, so the loop-end assert sees reality and story-7 mirroring holds.

### Rationale
The manifest already carries per-repo `{pr,verdict,state}`, `root_code_pr`, `bookkeeping_pr`, so it is the natural single source. Two small guards (delivery-time hold for Shape A, loop-end XOR) preserve the invariant's "no third Shape" safety without requiring the implementer and factory to share a mutable in-process PR map.

### Consequences
- A multi-app-repo task no longer dies at delivery (B-1 fixed).
- A task whose bookkeeping PR fails to raise is now a loud, non-zero failure (ties into the F3 fail-loud fix for B-5).
- Shape B (root touched) is explicitly sequenced: one root PR carries code + bookkeeping; the loop-end invariant reports `root_code_pr` set + `bookkeeping_pr` empty → holds.

### Revision triggers
A future change that raises the bookkeeping PR inside the implementer (not factory-run) would let the whole XOR collapse back into a single assert at delivery time. A schema change to the manifest's repo/PR fields must keep `root_code_pr` and `bookkeeping_pr` populated for the loop-end assert to remain meaningful.
