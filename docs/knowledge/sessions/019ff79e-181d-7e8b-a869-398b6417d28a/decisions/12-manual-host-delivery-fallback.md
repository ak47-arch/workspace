## Decision: If the implementer driver dies before host delivery, the operator completes it manually

**Status**: accepted
**Date**: 2026-08-15 01:14
**Task**: software-factory
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: When the driver dies after the container succeeded (outbox report present) but before delivery, the operator may complete host delivery manually, following the driver's e

### Context

The `implementer-revision-mode` run (container attempt 2, session
`cb6a90c1`) completed its work and wrote the outbox report at 23:11, but the
host-side driver was killed by a harness tool timeout (1900s <
`TIMEOUT_SEC` + delivery overhead) before `finalize_session_copy`,
`archive_run`, `transition`, and `push_and_pr` ran. The container's podman
process survived detached; the driver's delivery half did not.

### Problem

A fully successful implementation (all stories done, tests green, report
written) can be stranded without a PR, archive, session copy, or task tracking
when the driver process dies between container completion and host delivery.
Re-running the whole implementation is wasteful and violates "the implementer
owns the work" expectations; but leaving the work un-delivered loses decision-06
traceability.

### Alternatives

- **Re-run the entire implementation.** Rejected — the container already did the
  work; the run dir contains the durable artifacts.
- **Leave it and tell the user.** Rejected — the artifacts degrade (run dirs are
  cleaned), and the PR/archive/tracking are cheap to complete from what exists.
- **Manual host delivery by the operator (chosen).** Complete exactly the steps
  `push_and_pr`/`archive`/`finalize` would have run, mirroring the driver's
  conventions byte-for-byte: host-authored commit on the worktree branch → push
  branch → raise PR labeled `factory:needs-review` → PR-tracking rows (raise
  hook) → archive `docs/implementations/<date>-<slug>/` (brief + report +
  decisions) → copy the native session transcript over the knowledge-session
  stub → append impl decisions to the index → commit the workspace root.

### Decision

When the driver dies after the container succeeded (outbox report present) but
before delivery, the operator may complete host delivery manually, following the
driver's exact conventions. The manual commit messages and PR body should
explicitly record that delivery was manual (e.g. "(driver died at tool timeout
before push_and_pr)") so evaluations can distinguish manual from driver-native
deliveries.

### Rationale

The work is done and durable in the run dir; delivery is mechanical. Completing
it preserves decision-06 traceability and the PR lifecycle without re-doing the
implementation. Manual delivery is the exception path, not the rule.

### Consequences

- The fallback is documented and deliberate rather than ad-hoc repair.
- Evaluations can spot manual-delivery rows via the commit message marker.
- The real fix (preventing the death) is a longer tool timeout or detached
  invocation — this decision only covers the recovery path.

### Revision triggers

- If the driver gains `--resume`/delivery-only re-entry, manual delivery becomes
  obsolete — prefer that.
- If a manual delivery ever deviates from the driver's conventions (labels,
  row format, archive layout), the deviation must be noted in the commit
  message; if deviations recur, codify a `bin/deliver-run.sh` helper.
