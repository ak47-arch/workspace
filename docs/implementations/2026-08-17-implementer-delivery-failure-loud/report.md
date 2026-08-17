# Implementer Report — implementer-delivery-failure-loud

**Impl session**: afe61c92-6a16-4510-84ea-96d0f91badf6
**Date**: 2026-08-17
**PRD**: `docs/prd-queue/2026-08-17-implementer-delivery-failure-loud.md`

## Per-user-story status

### Story 1 — When the worktree branch push fails, the driver exits non-zero with a clear failure reason, no "Done (exit 0)". — **done**

- **What**: `bin/implementer-run.sh` `push_and_pr()` now guards the `git push`:
  a failed push prints `ERROR: git push of branch … to origin failed.` and returns 1
  (previously it continued past a failed push and misleadingly printed
  "Pushed branch …"). The `main` success path now routes `push_and_pr` failure to
  `fail_run` (see Story 3) with reason `delivery failed: branch push or PR
  creation`, which exits 1 — so "Done (exit 0)." is never printed.
- **Verified**: `bin/test-implementer-driver.sh` Test 17 (delivery push-fail) —
  asserts exit 1, `FAILED:` present, reason present, no `Pushed branch`, no
  `Done (exit 0)`. Pass.

### Story 2 — Push succeeds but `gh pr create` fails → driver exits non-zero with a clear reason; pushed branch left on the remote. — **done**

- **What**: `pr_url="$(gh_call pr create …)"` already returned 1 after 3 retry
  attempts (not a change), but it only took effect because the success path no
  longer swallows it (`push_and_pr || true` → guard). The branch-is-left-on-remote
  semantic is preserved (the function returns 1 after the push, never rewinds it).
- **Verified**: `bin/test-implementer-driver.sh` Test 18 (delivery pr-fail) —
  asserts exit 1, `FAILED:` + reason present, branch present on the bare remote,
  truthful `Pushed branch` line, no `PR raised`, no `Done (exit 0)`. Pass.
- **Note**: To make this testable through the existing `IMPLEMENTER_GH_BIN` seam
  (the PRD's prescribed mock), `push_and_pr` now calls `gh_call pr create` and
  checks `command -v "${IMPLEMENTER_GH_BIN:-gh}"` instead of the raw host `gh`
  binary. `gh label create` → `gh_call label create … || true`. Regression green.

### Story 3 — On delivery failure the task is reverted to `prd-ready` (existing `fail_run` semantics). — **done**

- **What**: The `main` success path now calls
  `if ! push_and_pr; then fail_run "delivery failed: branch push or PR creation"; fi`.
  Because `push_and_pr` is invoked inside the `if` guard, `set -e` cannot abort the
  script before `fail_run` runs (the PRD's guard-placement note). `fail_run` keeps
  its existing behavior: `stop_container`, `cleanup_run_dir --keep-logs`, archive
  (full report when the outbox has `report.md`, else a partial report), then
  `transition "prd-ready"` and `exit 1`.
- **Verified**: Both delivery tests assert the recording `transition-task.sh`
  received `prd-ready`. The no-report branch of `fail_run` (partial report) is
  covered by the existing Test 5 integration.

### Story 4 — On successful delivery, behavior unchanged: host-authored commit, push, PR with `factory:needs-review`, exit 0. — **done**

- **What**: No change to the happy path. `push_and_pr` still commits, pushes,
  and raises the PR tagged `factory:needs-review`; the dry-run success path is
  unchanged.
- **Verified**: All pre-existing tests stay green (see Verification results),
  including the dry-run success smoke (Test 5b) and the non-dry revise delivery
  (Test 16). `push_and_pr` under `--dry-run` still returns 0 before the gh path.

## Verification results

Command run (the PRD acceptance command), inside `/sandbox/worktree`:

```
bash bin/test-implementer-driver.sh
```

**Result: `71 passed, 0 failed`** (was 57 with the 2 new sections; all prior tests
green, plus 14 new delivery-failure assertions). `bash -n` syntax OK on both
`bin/implementer-run.sh` and `bin/test-implementer-driver.sh`.

### What was NOT verified here (UAT)
- Full non-dry **successful** delivery (real push + real `gh pr create` by the
  host) requires real network/GitHub credentials, which this sandbox deliberately
  lacks. The happy path is exercised via `--dry-run` smoke and the non-dry
  `--revise` delivery (push to a real local bare remote), and the PR-raising code
  is unchanged. UAT should confirm one real end-to-end run still raises a PR.

## UAT hand-off list

- Confirm a real driver run still delivers normally (host-authored commit, push,
  PR `factory:needs-review`, exit 0) against the live remote (Story 4).
- Confirm a pushed-then-PR-failed real run leaves the branch on `origin` and
  shows the `delivery failed: branch push or PR creation` FAILED reason (Story 2).
- The manifest-branch assertion (`resolve_repo` → `public-release` for
  `feed_analyser`) requires the `workspace-portability` sibling repo. In the
  test harness it now falls back to the factory workspace mount (`/workspace`)
  when it isn't present in the software-factory checkout; on the real host where
  the sibling lives inside the repo root, behavior is unchanged.

## Decisions emerged

- `decisions/01-delivery-failure-loud-gh-seam.md` — use the `IMPLEMENTER_GH_BIN`
  seam for delivery (`gh pr create` / `label` / `command -v`), enabling the PRD's
  mock-based delivery-failure tests.
- `decisions/02-delivery-failure-loud-local-nounset.md` — fix the latent bash
  `set -u` crash from a bare `local pr_url` (bash 5.2 leaves it unset).