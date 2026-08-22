## Decision

**Summary**: ## Decision

Implementer delivery failures route to the existing `fail_run` failure path
with an explicit guard + return discipline, instead of being swallowed into a
false success; and the driver's test fixture no longer depends on the
`workspace-portability` sibling repo being checked out.

**Status**: Accepted
**Date**: 2026-08-17
**Task**: [implementer-delivery-failure-loud](../../../../tasks/implementer-delivery-failure-loud.md)
**Project**: software-factory
**Session**: 8370f85b-3627-49fd-ad16-0df58e6c7cd4
**Summary**: ## Decision Implementer delivery failures route to the existing fail_run failure path with an explicit guard + return discipline, instead of being swallowed into a false

## Context

On 2026-08-17 a real implementer run hit a delivery failure (OAuth token
without `workflow` scope rejected the branch push; PR creation failed) yet
`bin/implementer-run.sh` printed `Done (exit 0).` and exited 0. The task was
left `in-progress` with no PR raised. Root cause: the success path called
`push_and_pr || true`, which swallowed delivery failures. With the headless CI
loop (`factory.yml`) now running the driver unattended, a swallowed delivery
failure makes a cloud run report success while delivering nothing.

## Problem

The success path discarded `push_and_pr`'s exit status; and under `set -e` the
`|| true` suppressed the abort, so a failed `git push` even printed misleading
"Pushed branch …" output as the script continued.

## Alternatives considered

- Keep `push_and_pr || true` and rely on `set -e` to abort: an unguarded failing
  call would abort the script before `fail_run` runs — rejected (must reach the
  failure path, not just die).
- Apply the same discipline to `bin/review-run.sh` (`post_pr_comment || true`):
  rejected / out of scope — a follow-up task can do it for the reviewer.
- Leave the test fixture copying the real `workspace-portability` manifest:
  rejected — absent in standalone checkouts makes the fixture non-self-contained
  and one test nondeterministically fail.

## Decision

1. **Driver (`bin/implementer-run.sh`)** — in `push_and_pr`, make `git push`
   failure explicit: `if ! git … push …; then echo "ERROR: …"; return 1; fi`
   (the `if !` guard also satisfies `set -e` by signalling that the function is
   being checked). In `main`, replace `push_and_pr || true` with
   `if ! push_and_pr; then fail_run "delivery failed: branch push or PR
   creation"; fi` — routing any non-zero delivery return (push or `gh pr create`)
   into the existing failure path (revert to `prd-ready`, archive partial
   report, exit 1). Successful delivery keeps today's behavior.
2. **Test fixture (`bin/test-implementer-driver.sh`)** — add failing-push mock
   and failing-`gh pr create` mock end-to-end (non-dry) tests asserting exit 1,
   `FAILED:` message, task reverted to `prd-ready`, and no misleading success
   output. Make `setup_fixture` generate a self-contained portability manifest
   fallback when the real `workspace-portability` repo isn't checked out.

## Rationale

- The PRD explicitly prescribed the guard placement and reusing `fail_run`; this
  implements exactly that. The explicit `return 1` on a failed push is required
  because the `|| true` context previously masked the failure, and the guard
  must be explicit so `set -e` routes into `fail_run` rather than aborting early.
- Making the fixture self-contained removes a real reproducibility gap (a
  standalone software-factory checkout without the sibling `workspace-portability`
  repo caused `resolve_repo`'s manifest test to fail) without changing any
  production behavior — the real manifest still wins when present.

## Consequences

- Delivery now fails truthfully: exit 1, `FAILED:` reason, task reverted to
  `prd-ready`, partial report archived. No false `Done (exit 0)`.
- When the push succeeds but PR creation fails, the branch is left on the remote
  and the failure path's re-run guidance applies (as intended).
- Good: the driver never strands a task in a false-success state; the headless CI
  loop can trust the exit code. Cost: a real delivery failure now tears down the
  run (expected).
- The reviewer-side `post_pr_comment || true` discipline remains as a follow-up.

## Revision triggers

- If a delivery failure is later deemed retryable (push/PR backoff/retry), this
  path is the insertion point (currently out of scope).
- If `bin/review-run.sh` gets the same failure discipline, revisit whether the
  two drivers should share a common delivery helper.
