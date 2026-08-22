## Decision: push_and_pr must honor the gh_call seam and fail loudly on delivery failure

**Status**: accepted
**Date**: 2026-08-17 20:05
**Task**: [implementer-delivery-failure-loud](../../../../tasks/implementer-delivery-failure-loud.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: In bin/implementer-run.sh: - Capture the git push status; on failure print ERROR: git push of branch … failed. and return 3 — never print Pushed branch … on a failed push

### Context
The implementer driver's success path delivered via `push_and_pr || true`,
which swallowed any delivery failure (rejected branch push, failed `gh pr
create`) and printed a misleading `Done (exit 0).` while no PR was raised. On
2026-08-17 a real run hit exactly this (OAuth token lacking `workflow` scope) —
the task stayed `in-progress` with no PR and the operator was misled. The PRD
directs a control-flow fix inside `bin/implementer-run.sh` only.

### Problem
Two defects had to be closed for delivery failures to surface truthfully:
1. `push_and_pr`'s `git push` result was not captured — the function continued
   past a rejected push, printed `Pushed branch …`, and the whole call was
   swallowed by `|| true`, so the run reported success while delivering nothing.
2. `push_and_pr` invoked `gh` and `command -v gh` literally instead of through
   the driver's existing `gh_call` seam (`${IMPLEMENTER_GH_BIN:-gh}`). This made
   the function untestable with a mocked gh binary and, in an environment
   without real `gh`, would make even the success path "fail" spuriously.

### Alternatives
- **Keep `gh` literal; only add the `if ! push_and_pr` guard.** Rejected: the
  PRD's own Testing decisions require mocking `IMPLEMENTER_GH_BIN` for the
  failing-`gh pr create` test — impossible while push_and_pr bypasses the seam.
- **Add retry/backoff or CI-sync handling.** Out of scope (PRD explicitly
  defers retry/backoff and the tracking-sync step).

### Decision
In `bin/implementer-run.sh`:
- Capture the `git push` status; on failure print `ERROR: git push of branch
  … failed.` and `return 3` — never print `Pushed branch …` on a failed push.
- Replace the literal `gh` invocations (`label create`, `pr create`) and the
  `command -v gh` guard with the `gh_call` seam (`${IMPLEMENTER_GH_BIN:-gh}`),
  so the PRD's mock seam actually works and the function is testable.
- Guard the success path: `if ! push_and_pr; then fail_run "delivery failed:
  branch push or PR creation"; fi` (explicit because `set -e` would otherwise
  abort before `fail_run` runs). `fail_run` already reverts to `prd-ready`,
  archives a partial report when needed, and exits 1.

### Rationale
- Smallest control-flow change satisfying the PRD; no new lifecycle machinery.
- Using the existing `gh_call` seam is the deterministic interpretation of the
  PRD's "mocks `IMPLEMENTER_GH_BIN` / `IMPLEMENTER_PODMAN_BIN`" testing seam.
- Routing into the existing `fail_run` preserves today's failure semantics
  (revert to `prd-ready`, archive, exit 1) with zero new machinery.

### Consequences
- A rejected push or failed `gh pr create` now exits 1 with a `FAILED:` reason
  and reverts the task to `prd-ready`; no more false `Done (exit 0)`.
- `gh` calls in `push_and_pr` are now mockable via `IMPLEMENTER_GH_BIN`.
- Successful delivery is unchanged (PR raised with `factory:needs-review`,
  exit 0) — confirmed by the unchanged existing tests.

### Revision triggers
- If the reviewer (`bin/review-run.sh`) should adopt the same discipline for
  its `post_pr_comment || true` — tracked as a follow-up task, not this one.
- If push/PR retry or backoff is later desired.
