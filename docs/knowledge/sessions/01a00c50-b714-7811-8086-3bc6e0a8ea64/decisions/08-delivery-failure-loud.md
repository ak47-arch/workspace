## Decision: Driver delivery failures must be loud — never false-success "Done (exit 0)"

**Status**: accepted
**Date**: 2026-08-17 17:27
**Task**: implementer-delivery-failure-loud
**Project**: software-factory
**Session**: sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/session.jsonl

### Context

2026-08-17, first real headless-bundle delivery: the worktree branch push was
rejected (OAuth token without `workflow` scope) and `gh pr create` failed, yet
`bin/implementer-run.sh` printed `Done (exit 0).` and exited 0 — the success
path calls `push_and_pr || true`, swallowing the failure. The task was left
`in-progress` with no PR: a false-success state that strands work and confuses
the operator. With the headless CI loop running the driver unattended, a
swallowed delivery failure would make a cloud run report success while
delivering nothing.

### Problem

Delivery failures (branch push, PR creation) must propagate: non-zero exit,
clear reason, task reverted — never a silent 0.

### Alternatives

- **Ignore / log-only** — rejected: strands tasks invisibly; unacceptable
  unattended.
- **Retry with backoff** — deferred as out of scope (the failure was
  environmental — token scope — not transient).

### Decision

The driver's success path stops swallowing delivery failures: capture
`push_and_pr`'s exit status; on failure enter the existing `fail_run` path
("delivery failed: branch push or PR creation") — task reverted to `prd-ready`,
partial report archived, exit 1 — and make `push_and_pr` itself return truthfully
(no misleading "Pushed branch …"/"PR raised …" on failure). Being implemented as
task `implementer-delivery-failure-loud`.

### Rationale

Unattended runs (CI) make silent failures costlier than loud ones: a loud
failure is diagnosable and re-runnable; a false success is a lost task. The
existing `fail_run` path already provides the revert/archive/cleanup semantics —
no new lifecycle machinery.

### Consequences

- Delivery failures surface as red CI steps with the reason, and the task
  reverts so the next `--pick` can retry it.
- The same discipline should later be applied to `review-run.sh`
  (`post_pr_comment || true`) — noted as follow-up in the PRD's out-of-scope.

### Revision triggers

- Delivery failures become transient enough that retry/backoff is warranted.
- The reviewer driver gets the same loud-failure treatment and the pattern is
  re-examined.
