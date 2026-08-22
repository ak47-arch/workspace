# PRD: Implementer must fail loudly when delivery (push/PR) fails

**Date**: 2026-08-17 16:45
**Status**: [Final](./manifest.json)
**Owner**: software-factory workspace
**Task**: [implementer-delivery-failure-loud](../tasks/implementer-delivery-failure-loud.md)
**Session**: [session.jsonl](../knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/session.jsonl)
**Decisions**:
  - [04-factory-run-headless-loop](../knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/04-factory-run-headless-loop.md)
## Problem statement

On 2026-08-17 a real implementer run hit a delivery failure — the branch push was
rejected (OAuth token without `workflow` scope) and PR creation failed — yet
`bin/implementer-run.sh` printed `Done (exit 0).` and exited 0. The task was left
`in-progress` with no PR raised: a false-success state that strands the work and
confuses the operator. Root cause: the success path calls `push_and_pr || true`,
which swallows delivery failures. This defect is load-bearing now that the
headless CI loop (`factory.yml`) runs the driver unattended — a swallowed
delivery failure there means the cloud run reports success while delivering
nothing.

## Solution overview

In the driver's success path, stop swallowing delivery failures:

- Capture `push_and_pr`'s exit status; on non-zero, enter the existing failure
  path (`fail_run`) with a clear reason (e.g. "delivery failed: branch push or
  PR creation") — task reverted to `prd-ready`, partial report archived, exit 1.
- Ensure `push_and_pr` itself propagates failure: `git push` (worktree branch)
  and `gh pr create` failures must surface as non-zero from the function
  (verify the actual mechanics under the driver's `set -euo pipefail` — the
  function currently continues past a failed push and misleadingly prints
  "Pushed branch …" and "PR raised …"; fix the message/return discipline so the
  outcome is truthful).
- Successful delivery keeps today's behavior (PR raised, exit 0) — regression
  must be green.

## User stories

1. When the worktree branch push fails, the driver exits non-zero and prints a
   clear failure reason — no "Done (exit 0)".
2. When the push succeeds but `gh pr create` fails, the driver exits non-zero
   with a clear failure reason (the pushed branch is left on the remote, and
   the failure path's re-run guidance applies).
3. On delivery failure, the task is reverted to `prd-ready` (existing
   `fail_run` semantics: partial report archived when the outbox lacks a full
   report).
4. On successful delivery, behavior is unchanged: host-authored commit, push,
   PR raised with `factory:needs-review`, exit 0.

## Implementation decisions

- Fix in `bin/implementer-run.sh` only (normal success path + `push_and_pr`
  return discipline). Do NOT touch `bin/review-run.sh` (its
  `post_pr_comment || true` pattern is out of scope — a follow-up task can
  apply the same discipline to the reviewer).
- Use the existing `fail_run` path — it already handles revert-to-`prd-ready`,
  cleanup, and archive. No new lifecycle machinery.
- Guard placement: `if ! push_and_pr; then fail_run "delivery failed …"; fi` —
  with `set -e`, the guard must be explicit (an unguarded failing call aborts
  the script before `fail_run` runs).

## Testing decisions

- Seam: `bin/test-implementer-driver.sh` already mocks `IMPLEMENTER_GH_BIN` /
  `IMPLEMENTER_PODMAN_BIN`. Add a failing-push mock (and a failing-`gh pr
  create` mock) and assert: exit code 1, "FAILED:" message present, task
  reverted to `prd-ready` (transition invoked), no misleading success output.
- Regression: existing 23 tests stay green; the dry-run success path unchanged.

## Architecture

No architecture change — a control-flow fix inside the driver's success path.
Data flow unchanged (implement → archive → commit worktree branch → push → PR).
The only delta: delivery outcome now feeds the failure path instead of being
discarded.

## Location (file map)

| Change | Path |
|---|---|
| `push_and_pr` return discipline + success-path guard | `bin/implementer-run.sh` |
| Delivery-failure tests (failing push / failing PR mocks) | `bin/test-implementer-driver.sh` |

Untouched: `bin/review-run.sh`, `bin/factory-run.sh`, `bin/transition-task.sh`,
`config/*.json`, `.github/workflows/factory.yml`.

## Acceptance (verification)

```bash
bash bin/test-implementer-driver.sh   # existing 23 + new delivery-failure tests, all pass
```

Plus manual: a driver run against a fixture with a failing push mock exits
non-zero with "FAILED:" and reverts the task (dry-run simulation acceptable).

## Out-of-scope

- Applying the same failure discipline to `bin/review-run.sh`
  (`post_pr_comment || true`).
- The CI workflow's tracking-sync step (already handled as operator infra).
- Retry/backoff for push/PR failures.

## Further notes

This is the first task planned to run through the new headless CI loop
(`factory.yml`) end-to-end — it doubles as the cloud-run validation.
