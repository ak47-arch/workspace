## Decision: Delivery uses the IMPLEMENTER_GH_BIN seam for gh

**Status**: accepted
**Date**: 2026-08-17
**Task**: implementer-delivery-failure-loud
**Project**: software-factory
**Session**: sessions/afe61c92-6a16-4510-84ea-96d0f91badf6/session.jsonl

### Context

`bin/implementer-run.sh` `push_and_pr()` (the driver's delivery step) called the
raw host `gh` binary directly: `command -v gh`, `gh label create …`, and
`gh pr create …` — while the rest of the driver routes gh through the
`gh_call()` seam (`${IMPLEMENTER_GH_BIN:-gh}`), already used by the revision
delivery path. The PRD's Testing decisions require the delivery-failure tests to
drive a failing `gh pr create` via `IMPLEMENTER_GH_BIN`, but the raw-`gh` calls
made that seam unusable for the normal delivery path.

### Problem

Without the seam, a failing-`gh pr create` cannot be injected for the normal
(non-revise) success path, so the delivery-failure/delivery-not-swallowed
behavior (PRD User stories 2) is not testable as specified.

### Alternatives

- **A. Keep raw `gh` and only test push-failure** (no PR-create mock). Rejected:
  leaves User story 2 untested, the exact defect the PRD targets.
- **B. Point plain `gh` at a mock via `PATH`** in the test. Possible but diverges
  from the driver's established `gh_call` seam and the PRD's stated mock seam.
- **C. Route all delivery gh calls through `gh_call`/`IMPLEMENTER_GH_BIN`**
  (chosen). Consistent with the revision path and the test seam.

### Decision

Use `gh_call` for `label create` and `pr create`, and gate the gh presence check
on `command -v "${IMPLEMENTER_GH_BIN:-gh}"`, inside `push_and_pr`. The
`|| true` on `label create` is preserved (inert metadata, Decision 01).

### Rationale

Reuses the existing seam, keeps behavior identical for real `gh` (the seam
defaults to `gh`), and makes the delivery-failure path deterministically testable
per the PRD's Testing decisions.

### Consequences

- `bin/test-implementer-driver.sh` Test 18 can now inject a failing-`gh pr create`
  mock and prove: exit 1, FAILED reason, branch left on remote, no misleading
  success output.
- No behavior change for real runs (`IMPLEMENTER_GH_BIN` unset → `gh`).
- Minor: `command -v` is now evaluated against the resolved seam binary instead of
  the literal `gh` (identical when the seam is unset).

### Revision triggers

- If the driver ever spawns `gh` in a path that must not use the test seam.