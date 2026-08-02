## Decision: PRD Queue Lifecycle

**Status**: accepted
**Date**: 2026-07-30 23:32
**Task**: end-to-end-traceability
**Project**: software-factory
**Session**: sessions/019fb3ee-9573-78d2-9d4b-a4bf49a742a7/session.jsonl

### Context

The PRD queue at `docs/prd-queue/` was accumulating PRDs indefinitely. Completed tasks left their PRDs in the queue alongside PRDs ready for implementation, making it unclear which items were actionable.

### Problem

A queue should show only what's ready to be picked up. Completed items should move out of the queue so the queue is always a clean list of actionable work.

### Alternatives

1. **Delete PRDs on completion** — loses the record. Rejected: the PRD is a valuable design artifact.
2. **Keep everything in the queue, mark completed** — queue becomes cluttered, no clear signal of what's actionable.
3. **Move to archive on completion** (chosen) — PRD moves from `docs/prd-queue/` to `docs/prd-archive/` when the task is marked complete. Same filename, just a different directory.

### Decision

The PRD queue is a real queue:
- A PRD enters `docs/prd-queue/` when a task transitions to `prd-ready`
- A PRD leaves `docs/prd-queue/` when the task transitions to `complete` — it moves to `docs/prd-archive/<date>-<slug>.md`
- The PRD filename never changes (no rename on move)
- `docs/prd-queue/` always shows only PRDs available for implementation

### Rationale

- The queue is always a clean list of actionable items
- No data loss — the archived PRD is still accessible via the task file or directly in `prd-archive/`
- Same filename means links referencing the archive path are stable
- Simple to implement — just `mv` between directories

### Consequences

- The product-layer skill's finalise step must include creating the task file (if not already created) and updating the PRD path
- The user or agent must move the PRD when marking a task complete
- Existing completed PRDs in the queue were backfilled to `prd-archive/`

### Revision triggers

- If the number of archived PRDs grows large enough that the flat directory needs organisation (e.g. by project or year)