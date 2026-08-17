# Implementer Report — implementer-delivery-failure-loud

**Impl session UUID**: 8370f85b-3627-49fd-ad16-0df58e6c7cd4
**Date**: 2026-08-17
**PRD**: `docs/prd-queue/2026-08-17-implementer-delivery-failure-loud.md`
**Status**: all stories implemented + verified

## Summary

Fixed a false-success delivery bug in `bin/implementer-run.sh`: the success
path previously called `push_and_pr || true`, swallowing branch-push / PR
creation failures and printing `Done (exit 0)` — stranding the task
`in-progress` with no PR raised. The delivery outcome now feeds the existing
`fail_run` failure path (revert to `prd-ready`, archive partial report, exit 1).

## User stories

### Story 1 — Push failure → non-zero exit + clear reason
- **done**
- **Evidence**: `bin/implementer-run.sh` — `push_and_pr` now wraps `git push`
  in `if ! git … push …; then echo "ERROR: git push … failed …"; return 1; fi`,
  so a failed push surfaces explicitly (under `set -e` the `if !` guard tells the
  shell the function is being checked) and never prints a misleading `Pushed
  branch …`. In `main`, the guard
  `if ! push_and_pr; then fail_run "delivery failed: branch push or PR creation"; fi`
  routes the non-zero return to `fail_run` → exit 1, no `Done (exit 0)`.
- **Verified**: `delivery push-fail` test — driver exits 1, `FAILED: delivery
  failed` printed, no `Pushed branch`, no false `Done (exit 0)`.

### Story 2 — Push ok but `gh pr create` fails → non-zero + clear reason
- **done**
- **Evidence**: `gh pr create` already returned 1 after 3 retries (leaving the
  branch pushed); now the new wealth guard routes that return to `fail_run`
  with reason `delivery failed: branch push or PR creation`, so the driver exits
  non-zero and the failure path's re-run guidance applies.
- **Verified**: `delivery pr-fail` test — driver exits 1, `FAILED: delivery
  failed` printed, `gh pr create` was attempted, branch really left on the
  remote (`git for-each-ref` shows `refs/heads/factory/deliv/*`), no misleading
  `PR raised (tagged…)`, no false `Done (exit 0)`.

### Story 3 — Delivery failure reverts task to `prd-ready`
- **done**
- **Evidence**: routing to the existing `fail_run` triggers its existing
  `transition "prd-ready"` (plus partial-report archive via the outbox/report
  path). No new lifecycle machinery.
- **Verified**: both `delivery push-fail` and `delivery pr-fail` tests — task
  file `**Status**` ends `prd-ready` and the mock transition-task log shows the
  `--to <prd-ready>` transition was invoked (observable because the tests run a
  mock transition-task that actually rewrites the task status, proving the
  revert from `in-progress` → `prd-ready`).

### Story 4 — Successful delivery unchanged
- **done**
- **Evidence**: the only normal-path change is the guard around `push_and_pr`;
  when it returns 0 the success flow (host commit, push, `gh pr create` →
  `factory:needs-review`, `Done (exit 0)`) is untouched. Dry-run path unchanged.
- **Verified**: existing 72-test suite regression green (see below), including
  the dry-run success smoke and revision-mode non-dry delivery.

## Verification results

Command (PRD acceptance):
```bash
bash bin/test-implementer-driver.sh
```
**Result: 72 passed, 0 failed.**

Covers: syntax/lint (`bash -n` both scripts; shellcheck skipped — not installed
in this sandbox), selection/resolution, brief writer, env allowlist, failure
path, end-to-end dry-run smoke, revise dry-run, revise negatives, revise non-dry
delivery, and the **15 new delivery-failure assertions** (7 push-fail + 8
pr-fail).

Manual (PRD): a full non-dry driver run against a fixture with a failing push
mock exits 1 with `FAILED:` and reverts the task — exactly what the
`delivery push-fail` test does end-to-end.

## Environment note (UAT hand-off)

- `workspace-portability/workspace_restore_manifest.json` is absent from this
  standalone worktree (it lives in a separate factory repo). This caused one
  pre-existing test — `resolve_repo manifest branch = public-release` — to fail
  in this sandbox before my change (the fixture's `cp` of the manifest silently
  no-op'd and `resolve_repo` fell back to `master`). I made the test fixture
  **self-contained**: `setup_fixture` now falls back to a generated manifest
  with the referenced entries when the real file is absent. With that, the
  entire suite passes here. On a host where `workspace-portability` is checked
  out, the copy path is unchanged (real manifest wins). No production behavior
  was altered — this is test-fixture robustness only.

## UAT hand-off list

1. **`bin/implementer-run.sh`** — review the changed `push_and_pr` (explicit
   push-failure return + truthfulness) and the `if ! push_and_pr; then
   fail_run "delivery failed: branch push or PR creation"; fi` guard in `main`.
2. **`bin/test-implementer-driver.sh`** — review the new `delivery push-fail`
   / `delivery pr-fail` tests and the `setup_fixture` manifest fallback.
3. **The actual CI loop** (`factory.yml`) — this task doubles as the first real
   end-to-end cloud-run validation of the headless loop; confirm the delivered
   PR lands and the cloud run reports truthfully.
4. Confirm no secrets/environment leaks in the delivery logs (env allowlist
   unchanged; `GITHUB_TOKEN` exclusion already covered by existing tests).

## Decisions emerged

- `outbox/decisions/01-implementer-delivery-failure-loud.md` — delivery
  failure now feeds the failure path instead of being swallowed (records the
  guard + return discipline and the self-contained test-fixture manifest).

## Out of scope (per PRD, intentionally untouched)

- `bin/review-run.sh` (`post_pr_comment || true` discipline) — follow-up task.
- `bin/factory-run.sh`, `bin/transition-task.sh`, `config/*.json`,
  `.github/workflows/factory.yml`.