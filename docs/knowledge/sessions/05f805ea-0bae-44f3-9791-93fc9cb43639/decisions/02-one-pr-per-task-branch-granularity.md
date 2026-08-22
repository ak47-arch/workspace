## Decision: One PR per task — lifecycle bookkeeping commits onto the task's own branch

**Status**: accepted
**Date**: 2026-08-22
**Task**: typed-trail-integrity
**Project**: software-factory
**Session**: 05f805ea-0bae-44f3-9791-93fc9cb43639

**Summary**: Task transitions (`prd-ready` → `in-progress` → `in-review` →
`complete`) commit onto the task branch (a `factory/<slug>/<ts>` branch minted
*before* the first transition), so the full task lifecycle — declaration +
implementation + review bookkeeping — rides up in a single pull request. There
is never a separate bookkeeping commit on a protected default branch.

### Context

The prior driver flow cut the implementation worktree branch at implementation
time, after earlier transitions (`prd-ready`, `in-progress`) had already been
committed onto the host's current branch — the protected default. Those
bookkeeping commits were therefore stranded on local `master`: branch
protection rejected pushing them directly, and only `bin/merge-pr.sh` could
carry tracking up later. The result was a second, disjoint commit stream that
had to be carried by a later merge, producing the "two PRs" confusion.

Git history is the wrong store for lifecycle state. The task's lifecycle state
already lives authoritatively in the routing manifest (`docs/prd/manifest.json`
for PRDs) and the task file's own `**Status**:` line. The separation between
"tracking commits" and "implementation commits" was accidental — both are
attributes of the same task and should share the same PR stream.

### Decision

1. **Branch first, transition after.** The driver mints
   `factory/<slug>/<ts>` before the first lifecycle transition for the task.
2. **Transitions target the task branch.** `transition-task.sh` gains a
   `--branch` option (and a `--workspace` override so it can operate inside
   the run-dir worktree clone). The driver's `transition()` passes the
   worktree branch; the transition commit lands on the task branch, not on the
   current default.
3. **One PR carries the task.** The pushed branch contains the transition
   commits and the implementation commits together; the PR diff is the entire
   task. No separate bookkeeping PR, no stranded tracking on master.

### Consequences

- A task's PR shows its whole lifecycle — planning/transition + implementation
  docs — as a single reviewable diff (observed: PR #46 carries
  `prd-ready` → `in-progress` → `pr-tracking` → `implementation`).
- Transition granularity stays intact (the audit trail of a task's state
  is preserved as separate commits on the branch); only the *delivery path*
  is unified.
- Existing local bookkeeping commits stranded on master can be dropped once
  the same commits are present on the PR branch (verified for this run).