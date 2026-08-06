## Decision: PRD moves to archive only after UAT passes and the user gives go-ahead

**Status**: accepted
**Date**: 2026-08-06
**Task**: x-capture-instrument
**Project**: feed-analyser
**Session**: sessions/019fd314-9339-7a30-9b8b-f6d8892b5226/session.jsonl

### Context

The x-capture-instrument PRD was moved from `docs/prd-queue/` to
`docs/prd-archive/` and its task marked `complete` immediately after code was
written and unit tests passed. On user testing (UAT), the extension was found
not working as intended (flickering pill, unclickable pill, missing links,
broken highlight feature). The task had to be reverted: PRD moved back to the
queue, status back to `prd-ready`.

### Problem

"Code written + unit tests pass" is not the same as "done." The PRD lifecycle
convention (a PRD leaves the queue only when its task is `complete`) treated
completion as shipping code, which let non-working features be archived and
marked done.

### Alternatives

- **Archive on code-complete** — Rejected: caused a premature archive and a
  revert when UAT failed.
- **Require UAT + user sign-off before archiving (chosen)** — a PRD stays in
  the queue until the delivered feature passes user acceptance testing AND the
  user explicitly gives the go-ahead.

### Decision

- A PRD moves from `docs/prd-queue/` to `docs/prd-archive/` **only when**:
  1. the implementation is delivered, **and**
  2. **all UAT testing is complete** and the user confirms it works as
     intended, **and**
  3. the user gives the go-ahead to finalize.
- Until then, the task status stays `prd-ready` (not `complete`) and the PRD
  remains in the queue.
- When a PRD that was archived must be reopened, move it back to
  `docs/prd-queue/`, set the task to `prd-ready`, and update the Plan artifact
  path — exactly as done for this task on 2026-08-06.

### Rationale

- Prevents non-working or incomplete features from being archived and marked
  done.
- Keeps the queue honest as a list of actionable, unconfirmed work.
- The archive becomes a record of genuinely shipped, verified features.

### Consequences

- For x-capture-instrument: PRD back in `prd-queue/`, task back to
  `prd-ready`, Plan path re-pointed. The PRD was updated (Rev 2) to reflect
  the session's decisions (single-intent scope, rich links) before any further
  implementation.
- This supersedes/refines the earlier PRD-queue-lifecycle decision to tie
  "complete" to UAT + user sign-off rather than code-complete.

### Revision triggers

- If a project's workflow introduces a distinct, more precise definition of
  "done" (e.g. an explicit QA gate) that should drive archiving instead.
- If the user finds the manual queue/archive bookkeeping burdensome and wants
  it automated.
