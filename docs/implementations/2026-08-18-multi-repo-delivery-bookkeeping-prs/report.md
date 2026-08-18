# Implementer Report — multi-repo-delivery-bookkeeping-prs

**Task**: multi-repo-delivery-bookkeeping-prs
**Impl session UUID**: c63649d5-f660-4494-af41-d0025d02f728
**Date**: 2026-08-18

## Summary

Implemented multi-repo delivery with PR-based bookkeeping for the software-factory
workspace. A task now declares a set of repos (`**Repos:**` header) and delivers
through two shapes only: **Shape A** (root not touched) = N code PRs + 1 docs-only
**bookkeeping PR** on the root → N+1 PRs; **Shape B** (root touched) = the root
code PR carries code + bookkeeping as separate commits → N PRs. The direct-push
streams are retired. All four acceptance test suites pass (215 tests).

## Per-user-story status + evidence

| # | Story | Status | Evidence |
|---|---|---|---|
| 1 | Single app repo → exactly 2 PRs (1 code + 1 bookkeeping) | **done** | `resolve_repo_set` (Shape A, root not touched) + `deliver_multi` (1 code PR) + `factory-run.sh raise_bookkeeping_pr` (1 docs-only bookkeeping PR). Tested: `test-factory-run.sh` "bookkeeping PR raised (docs-only, factory:bookkeeping)". |
| 2 | N app repos → exactly N+1 PRs | **done** | `prepare_run_dirs_multi` (one worktree per repo), `deliver_multi` loops per dirty worktree. Tested: `test-implementer-driver.sh` "2 per-worktree branches pushed" + "exactly 2 gh pr create calls". |
| 3 | Workspace root only → exactly 1 PR (code + bookkeeping commits) | **done** | `deliver_multi` Shape-B branch: root worktree gets a **CODE commit** (non-docs) then a **BOOKKEEPING commit** (docs-only) on the same branch → one root PR. Tested: "Shape B collapse — root CODE commit then BOOKKEEPING commit" (log shows `bookkeeping` after `code`). |
| 4 | Hybrid (root + app repos) | **done** | Same Shape-B root handling + per-app code PRs (N total). `ROOT_TOUCHED=1` hybrid fixture in `test-implementer-driver.sh`. |
| 5 | Delivery invariant holds; violation fails loud | **done** | `assert_delivery_invariant` (the A/B XOR), invoked after Shape-B delivery and after the loop end. Tested: "violation (root+bk both present) fails loud" and "valid XOR passes". |
| 6 | Bookkeeping tripwire (docs-only) | **done** | `bookkeeping_tripwire` + a second check in `raise_bookkeeping_pr` fail on any non-`docs/` path. Tested: "code-path (bin/) in bookkeeping fails hard" + "docs-only staged diff passes". |
| 7 | Run manifest written for every run, shown at end, mirrored into bookkeeping PR body | **done** | `write_run_manifest` (schema per PRD) written by `deliver_multi`; `print_run_manifest` surfaces at loop end (success or failure); `raise_bookkeeping_pr` embeds the manifest in the PR body. Tested: "run manifest written", "run manifest printed at loop end". |
| 8 | Pickup gate skips task with open `factory/<slug>` PR | **done** | `.github/workflows/factory.yml` "Pickup gate" step runs `gh pr list --search "[factory] <slug>" --state open` across the workspace + repo_map targets, sets `PICKUP_SKIP=true`, and gates the headless loop; loud skip reason printed. |
| 9 | REQUEST_CHANGES → revise only rejected repos | **done** | `factory-run.sh multi_headless_loop`: on REQUEST_CHANGES only that repo's PR is passed to `implementer-run.sh --revise`; approved repos are never revised. Tested: "revise targets ONLY the rejected repo (#12)" and "approved repo (#11) was NOT revised". |
| 10 | merge-pr.sh accepts the PR set, pre-flights all-open, merges each, per-PR Merge rows, complete only when whole set merged | **done** | `merge-pr.sh` rewritten: multiple `<pr>` args, pre-flight `state == OPEN` for every PR (abort before any merge), per-PR `Merge:` row (attributed by PR), and `transition-task.sh --to complete` only when the whole set merged. Tested: `test-merge-pr.sh` (14 tests) incl. "pre-flight: a non-open PR aborts the set (exit 2, no double-merge)", "per-PR Merge rows (2)", "task transitions to complete only when the whole set is merged". |
| 11 | Direct-push streams retired | **done** | `merge-pr.sh` no longer pushes master (test asserts "story 11: no master push"); `factory.yml` "Sync tracking commits to master" step replaced by "Verify bookkeeping stream (no direct master push)". |

## Files changed (worktree)

- `bin/implementer-run.sh` — `resolve_repo_set`, `prepare_run_dirs_multi`,
  `write_brief_multi`, `deliver_multi` (per-worktree + Shape B collapse),
  `assert_delivery_invariant`, `bookkeeping_tripwire`, `write_run_manifest`,
  `print_run_manifest`, `parse_repos_header`, `repo_key_from_path`,
  `manifest_branch_for`, `main_multi`, `MULTI_MODE` dispatch + per-PR tracking rows.
- `bin/factory-run.sh` — `find_manifest`, `print_run_manifest`,
  `resolve_pr_set_from_manifest`, `manifest_is_shape_a`, `raise_bookkeeping_pr`
  (Shape A docs-only, tripwire), `multi_headless_loop` (per-repo revision),
  headless dispatch to the PR set + bookkeeping + manifest at loop end.
- `bin/review-run.sh` — PR-set support (`review_one` loop), run-dir
  report (`<run>/reviews/<slug>-<pr>.md`) + verdict (`<run>/verdicts/<slug>-<pr>.verdict`).
- `bin/merge-pr.sh` — rewritten for a PR set: pre-flight, per-PR merge + Merge row,
  complete transition, no master push.
- `.github/workflows/factory.yml` — pickup gate (story 8) + sync-step retirement
  (story 11).
- `docs/reference/implementer-agent.md`, `docs/reference/reviewer-agent.md` — artefact
  maps updated for multi-repo delivery.
- `bin/test-implementer-driver.sh`, `bin/test-factory-run.sh`, `bin/test-review-driver.sh`,
  `bin/test-merge-pr.sh` — extended with multi-repo fixtures + assertions.
- `config/implementer.json` — unchanged (repo_map already covers all repos; validation
  of `**Repos:**` lives in `resolve_repo_set`). No change to the map itself, per PRD.

## Verification results

All four PRD acceptance commands run and **pass** in the worktree:

```
bash bin/test-implementer-driver.sh   # 87 passed, 0 failed
bash bin/test-review-driver.sh        # 67 passed, 0 failed
bash bin/test-factory-run.sh          # 47 passed, 0 failed
bash bin/test-merge-pr.sh             # 14 passed, 0 failed
```

`bash -n` clean on every modified `bin/*.sh`. The live CI workflow
(`.github/workflows/factory.yml`) was edited to the PRD's specification but is an
operational YAML that cannot be executed in this sandbox (no runner/gh/secrets) —
see UAT.

## UAT hand-off list

1. **Live smoke (PRD "Plus a live smoke")**: run one real two-repo PRD through
   `bin/factory-run.sh --headless --task <slug>` on a scratch branch and confirm
   exactly N code PRs + 1 bookkeeping PR (or the Shape-B collapse), the invariant
   holds, the manifest is printed, and the loop stops at APPROVE. Requires real
   `gh` + container runtime + network — not runnable in this sandbox.
2. **`.github/workflows/factory.yml`**: validate the pickup-gate step and the
   "Verify bookkeeping stream" step on a real push (no YAML linter available here;
   structural check only). Confirm the retired `git add -A`/`push origin master`
   sync step is gone and nothing re-introduces a direct master push.
3. **Operator capstone (companion task)**: after UAT merge, apply + verify the
   workspace branch protection (`branch-protection-merge-only`) — explicitly
   out-of-scope for this task.
4. **Bookkeeping PR merge**: a Shape-A bookkeeping PR (docs-only) is raised by the
   loop and must be merged by the user at UAT (never auto-merged).
5. **`bin/merge-pr.sh <set>`**: run the manual UAT-completion pass with the full PR
   set (code PRs + bookkeeping PR) and confirm per-PR Merge rows + the `complete`
   transition fire only when the whole set is merged.
6. **Config**: no repo_map change was needed; if a future PRD declares a repo not in
   `config/implementer.json` repo_map, the run fails loudly naming it (F1) — the
   correct fix is to add that repo to the map (operator action).

## Decisions emerged

- `outbox/decisions/01-run-manifest-repo-keys.md` — manifest `repos` keys are the
  canonical repo keys (`workspace` for root, else the repo_map value dir), matching
  branch naming; the PRD's illustrative `goal-agent`/`llamacpp_inference_server`
  sample keys are GitHub names, not repo_map keys.
- `outbox/decisions/02-delivery-invariant-assertion-point.md` — the A/B invariant is
  asserted where it can hold: after Shape-B delivery (implementer) and at loop end
  after the bookkeeping PR is raised (factory-run), not mid-implementer for Shape A
  (whose bookkeeping PR is legitimately pending until loop end).
- `outbox/decisions/03-multi-repo-array-scoping.md` — the driver's multi-repo
  associative arrays use `declare -gA` so they survive being sourced from within a
  test harness function (`source_driver`).
