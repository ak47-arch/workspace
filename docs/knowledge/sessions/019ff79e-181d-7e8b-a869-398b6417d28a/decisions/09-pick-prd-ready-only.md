## Decision: `--pick` selects only `prd-ready` tasks with Final PRDs; `--task` is the explicit override

**Status**: accepted
**Date**: 2026-08-14 22:37
**Task**: task-selection-abstraction-layer
**Project**: software-factory
**Session**: sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl

### Context

The factory accumulated stale Final PRDs: `code-review-agent` was merged
(`f7f672f`) but its task stayed `in-review`, and `implementer-ponytail` was
`in-review` (PR #2 review-blocked). `--pick` keyed only on "PRD Final AND task
not in-progress", so it would re-implement merged/blocked lineages or raise
competing PRs. The queue showed three "pickable" Final PRDs, only one of which
was actually wanted.

### Problem

The automatic task-selection predicate was stale: it encoded one state
(in-progress = concurrent owner) instead of the lifecycle's actual queued-entry
state, so stale lineages stayed pickable and `--pick` became a hazard.

### Alternatives

- **Remove `--pick` entirely.** Rejected — it is the deterministic base layer
  of the queued `task-selection-abstraction-layer` roadmap, and hiding a stale
  predicate by deleting the feature treats the symptom.
- **Skip tasks whose PR tracking shows a `Merge:` row or a REQUEST_CHANGES
  verdict (heuristic).** Rejected — redundant and incomplete: requires parsing
  PR-tracking rows and misses holes (review in flight with no Review row yet,
  crashed runs). The task status field is canonical.
- **Require task status `prd-ready` for `--pick` (chosen).** The lifecycle
  already defines pickability: `prd-ready` is the queued-entry state; the three
  other in-flight states are not.

### Decision

`resolve_prd` in `bin/implementer-run.sh`: `--pick` selects the oldest Final PRD
whose task file status is `**Status**: prd-ready`. `in-prd`, `in-progress`,
`in-review`, and `complete` tasks are never picked. `--task <slug>` remains an
explicit operator override, NOT gated on task status. Error message updated.

### Rationale

One canonical field decides it — no parsing, no new failure modes. Explicit
invocation (`--task`) is operator intent and stays permissive; automatic
selection (`--pick`) is strict. Test coverage now includes a stale
oldest-Final/in-review case that must be skipped (implementer-driver 35/35).

### Consequences

- `--pick` now resolves to exactly the queued task; stale lineages can no
  longer be re-implemented or spawn competing PRs.
- Completed tasks still need bookkeeping (transition to `complete` archives the
  PRD) — `code-review-agent` was transitioned as hygiene, but the predicate no
  longer depends on it for safety.
- The queued `task-selection-abstraction-layer` task builds on this strict base.

### Revision triggers

- If the lifecycle gains a state where `prd-ready` is not the entry state for
  implementation, revisit the predicate.
- If `--pick` should ever consider task priority/state reasoning (the
  abstraction-layer task), extend this predicate — do not loosen it.
