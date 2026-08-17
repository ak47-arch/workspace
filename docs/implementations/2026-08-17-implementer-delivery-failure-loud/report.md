# Implementer Report — implementer-delivery-failure-loud

**Session**: 82eae199-b670-4199-99f3-c1c9edcfb749
**Date**: 2026-08-17
**Worktree**: /sandbox/worktree

## Summary

Fixed the driver's success path so delivery failures (branch push and/or PR
creation) fail loudly instead of being swallowed by the old `push_and_pr ||
true`. On any delivery failure the run now exits non-zero, prints a clear
`FAILED:` reason, and reverts the task to `prd-ready` via the existing
`fail_run` path. Successful delivery behavior is unchanged.

## User stories

### Story 1 — When the worktree branch push fails, the driver exits non-zero and prints a clear failure reason (no "Done (exit 0)")
**Status**: done

- `bin/implementer-run.sh` `push_and_pr()`: the worktree `git push` is now
  wrapped in an explicit failure check that prints
  `ERROR: branch push failed for <branch>.` and `return 1` — instead of
  continuing and misleadingly printing `Pushed branch …`.
- Success path replaced `push_and_pr || true` with
  `if ! push_and_pr; then fail_run "delivery failed: branch push or PR creation"; fi`.
- Verification: `delivery: push-fail driver exits 1`, `delivery: push-fail
  prints clear FAILED reason`, `delivery: push-fail has no misleading success
  output` — all pass.

### Story 2 — When the push succeeds but `gh pr create` fails, the driver exits non-zero with a clear failure reason
**Status**: done

- `push_and_pr()`: the `gh pr create` command substitution is now guarded with
  an explicit `|| { echo "ERROR: gh pr create failed for <branch> (branch
  remains pushed)."; return 1; }`.
- Verification: `delivery: pr-fail driver exits 1`, `delivery: pr-fail prints
  clear FAILED reason`, `delivery: pr-fail has no misleading success output`,
  `delivery: pr-fail leaves pushed branch on the remote` — all pass.

### Story 3 — On delivery failure, the task is reverted to `prd-ready` (existing `fail_run` semantics)
**Status**: done

- The guard routes into the existing `fail_run`, which invokes
  `transition "prd-ready"` (revert) and archives the partial/full report when
  the outbox has one.
- Verification: `delivery: push-fail reverts task to prd-ready (transition
  invoked)`, `delivery: pr-fail reverts task to prd-ready (transition
  invoked)`, `delivery: push-fail archives partial/full report` — all pass.
- The `if !` guard is required because with `set -e` an unguarded failing
  `push_and_pr` call would abort the script before `fail_run` runs (matching
  the PRD's guard-placement decision).

### Story 4 — On successful delivery, behavior is unchanged
**Status**: done

- No change to the success path's normal flow; only the failure branch was
  added. The dry-run success smoke and the revision non-dry success tests
  remain green.

## Verification results

- Ran `bash bin/test-implementer-driver.sh` inside the worktree.
  **Result: 65 passed, 1 failed.**
- **New delivery-failure tests (10 assertions, all pass):**
  - `delivery: push-fail driver exits 1`
  - `delivery: push-fail prints clear FAILED reason`
  - `delivery: push-fail has no misleading success output`
  - `delivery: push-fail reverts task to prd-ready (transition invoked)`
  - `delivery: push-fail archives partial/full report`
  - `delivery: pr-fail driver exits 1`
  - `delivery: pr-fail prints clear FAILED reason`
  - `delivery: pr-fail has no misleading success output`
  - `delivery: pr-fail leaves pushed branch on the remote`
  - `delivery: pr-fail reverts task to prd-ready (transition invoked)`
- **UAT remaining (pre-existing environmental, not a regression):**
  - `resolve_repo MANIFEST_BRANCH = 'master' — expected public-release` fails
    because the worktree clone does not contain `workspace-portability/`
    (gitignored — `.gitignore` line 22), so the test fixture's manifest copy
    no-ops and `resolve_repo` falls back to `master` for `feed_analyser`. This
    directory IS present in the real `/workspace`, so the test passes in the
    host repo. **This failure exists independently of this PRD's changes** — it
    is caused by the workspace-portability artifact being absent from a fresh
    clone, not by the delivery-failure work.
- Manual/out-of-sandbox: a real driver run against a fixture with a failing
  push mock exits non-zero with `FAILED:` and reverts the task — simulated by
  the two new non-dry delivery tests (which exercise the real `main` via mock
  podman/git/gh). The real `gh pr create` OAuth rejection path is not
  re-testable here (no GitHub credentials in the sandbox); asserts rely on the
  failing-`pr create` mock.

## UAT hand-off list

1. Confirm the `resolve_repo` manifest-branch test passes in the host CI where
   `workspace-portability/` is present (it should — this sandbox lacks the
   gitignored artifact).
2. Optionally run a real driver run against a forced `git push` rejection to
   observe the non-zero exit + `FAILED:` + `prd-ready` revert end-to-end with a
   live GitHub remote.
3. Confirm `bin/review-run.sh` is untouched (per PRD out-of-scope) — no
   delivery-discipline change applied to the reviewer.

## Files changed

| Path | Change |
|---|---|
| `bin/implementer-run.sh` | `push_and_pr` return discipline (push + `gh pr create`), success-path guard `if ! push_and_pr; then fail_run …` |
| `bin/test-implementer-driver.sh` | Added delivery-failure mocks (failing push git, failing `pr create` gh, transition stub) + Test 17/18 |

Untouched: `bin/review-run.sh`, `bin/factory-run.sh`, `bin/transition-task.sh`,
`config/*.json`, `.github/workflows/factory.yml`.

## Decisions emerged

- `01-implementer-delivery-failure-loud.md` — guard placement + return
  discipline inside `push_and_pr` (why `if !` and explicit returns are both
  required under `set -e`).