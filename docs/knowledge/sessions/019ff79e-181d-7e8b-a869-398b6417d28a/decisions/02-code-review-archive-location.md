## Decision: Code-review reports archive under docs/code-reviews/, not docs/reviews/

**Status**: accepted
**Date**: 2026-08-13 23:00
**Task**: code-review-agent
**Project**: software-factory
**Session**: sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl

### Context

Designing where the code-review agent's output should be archived. The earliest
draft proposed `docs/reviews/<date>-<slug>/` by analogy with
`docs/implementations/` (the implementer's archive root).

### Problem

`docs/reviews/` is **already in use** — it stores flat `<date>-<slug>.md` PRD-gate
reports produced by the `prd-reviewer` agent (e.g.
`2026-08-10-implementer-agent.md`). Two different "review" artifacts under the same
root would be conflated: PRD-gate (pre-implementation, readiness) vs code review
(post-implementation, PR).

### Alternatives

- **Reuse `docs/reviews/`** — ambiguous and would mix two gate types with different
  schemas and consumers. Rejected.
- **`docs/code-reviews/<date>-<slug>/`** — chosen: distinct root, named for the
  artifact, and a directory-per-run like `docs/implementations/` (report + brief +
  decisions), keeping the code-review gate visually separate from PRD-gate reports.

### Decision

Code-review archives live at `docs/code-reviews/<date>-<slug>/` (mirroring
`docs/implementations/` layout). `docs/reviews/` stays exclusively for PRD-gate
reports. `config/reviewer.json` carries `reviews_root: docs/code-reviews`.

### Rationale

Two gates, two roots: a future agent (or the user) can find "was this PR reviewed?"
in one place without colliding with "was this PRD ready?". Naming communicates the
stage (code review) vs the artifact class (reviews of PRDs).

### Consequences

- New archive root; the driver test suite must assert the correct destination.
- `docs/reviews/` semantics stay single-purpose (PRD gate). Consider renaming it to
  `docs/prd-reviews/` later for symmetry (not required now).

### Revision triggers

- If PRD-gate reports are renamed/moved (e.g. `docs/prd-reviews/`), revisit whether
  `docs/code-reviews/` naming should follow suit.
- If reviews get a machine-readable consumer, the directory-per-run layout may need
  an index file.