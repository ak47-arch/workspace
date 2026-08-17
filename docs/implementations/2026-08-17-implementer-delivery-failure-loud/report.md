# Implementer Report — `implementer-delivery-failure-loud`

**Task**: implementer-delivery-failure-loud
**Impl session**: d5492a5c-6c07-4f58-b410-5feefa2a43c2
**Date**: 2026-08-17

## Per-user-story status

### Story 1 — When the worktree branch push fails, the driver exits non-zero with a clear failure reason — no "Done (exit 0)".
**Status**: done
**Evidence**:
- `bin/implementer-run.sh` `push_and_pr()`: the `git push` result is now captured —
  `if ! git -C "$WORKTREE" push -u origin "$WORKTREE_BRANCH"; then echo "ERROR: git push of branch … failed." >&2; return 3; fi` — so a rejected/dead push surfaces as non-zero and the misleading `Pushed branch …` line is no longer printed.
- Success-path guard: `if ! push_and_pr; then fail_run "delivery failed: branch push or PR creation"; fi` (replaces the old `push_and_pr || true`), so the driver exits 1 with a `FAILED:` reason.
- **Verified**: Test 17 (`── delivery failure: branch push rejected ──`): driver exits 1; `FAILED:` + `delivery failed` present; no `Done (exit 0)`, no `Pushed branch`, no `PR raised`.

### Story 2 — When push succeeds but `gh pr create` fails, the driver exits non-zero with a clear reason (branch left on remote).
**Status**: done
**Evidence**:
- `push_and_pr()` now routes `gh` through the `gh_call` seam (`${IMPLEMENTER_GH_BIN:-gh}`) for both `label create` and the retried `pr create`, and the availability guard uses `command -v "${IMPLEMENTER_GH_BIN:-gh}"`. On persistent `pr create` failure the function returns 1; the success-path guard routes to `fail_run`.
- **Verified**: Test 18 (`── delivery failure: gh pr create fails (branch left pushed) ──`): driver exits 1; `FAILED:` reason present; no `Done (exit 0)` / `PR raised`; `gh pr create` was attempted (retried); the pushed `factory/*` branch remains on the remote.

### Story 3 — On delivery failure the task is reverted to `prd-ready` (existing `fail_run` semantics).
**Status**: done
**Evidence**: Routing into the existing `fail_run` (unchanged) → it invokes `transition "prd-ready"` (non-revision mode), archives a partial report when the outbox lacks a full one, and exits 1. No new lifecycle machinery.
- **Verified**: In both Test 17 and Test 18 the transition log records `--to prd-ready` and the task file's `**Status**` becomes `prd-ready`.

### Story 4 — On successful delivery, behavior is unchanged: host-authored commit, push, PR raised with `factory:needs-review`, exit 0.
**Status**: done
**Evidence**: The success path is otherwise untouched. The regression suite (all pre-existing tests including the end-to-end revise-delivery test and the `--dry-run` smoke) stays green.
- **Verified**: All existing tests pass except one pre-existing environment-only failure (see Verification results).

## Verification results

Command: `bash bin/test-implementer-driver.sh` (run inside the worktree).

Result: **71 passed, 1 failed.**

- **New delivery-failure tests: 16/16 pass** (Test 17: 9/9; Test 18: 7/7).
- **Regression: all existing tests stay green** except one pre-existing, environment-only failure:
  - `resolve_repo MANIFEST_BRANCH = 'master' — expected public-release`. This failure predates this task (it fails identically on a clean baseline before my changes). Cause: `bin/test-implementer-driver.sh` copies `workspace-portability/workspace_restore_manifest.json` from the repo root into its fixture, but that file is **gitignored** (`/workspace-portability/` in `.gitignore`) and therefore absent from the disposable worktree clone in this sandbox. `resolve_repo` then falls back to `master`. On the host (and in the reviewer's `/workspace` checkout) the gitignored file exists, so this assertion passes there. **No code in this task touches `resolve_repo`, the manifest, or that assertion.**
- Manual dry-run simulation equivalent: my isolated repro confirmed the failing-push path exits non-zero with `FAILED: delivery failed: branch push or PR creation` and reverts the task.

## UAT hand-off list

1. Confirm the `resolve_repo MANIFEST_BRANCH` test passes in the host/CI environment where `workspace-portability/workspace_restore_manifest.json` is present (it is gitignored and absent from this sandbox worktree; this is not a regression from this task).
2. Review the `gh_call` seam change in `push_and_pr` (the PRD's stated `IMPLEMENTER_GH_BIN` mock seam now actually drives `push_and_pr`'s gh calls). This was required to test Story 2.
3. Sanity-check the manual driver run against a fixture with a failing push mock (the PRD's manual acceptance): expected exit 1, a `FAILED:` message, and the task reverted to `prd-ready`.

## Decisions emerged

- `outbox/decisions/01-implementer-delivery-fail-loudly.md` — `push_and_pr` must honor the `gh_call` seam and fail loudly on delivery failure.
