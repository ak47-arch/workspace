# Implementer Report — implementer-revision-mode

**Task**: implementer-revision-mode
**Impl session UUID**: cb6a90c1-f8d0-4da5-b413-1f82a0f32376
**Project**: software-factory
**Date**: 2026-08-14

## Summary

Implemented `bin/implementer-run.sh --revise <pr>` (revision mode, decision 08)
in the factory worktree: it resolves an open PR → task slug → original
implementation session UUID → newest REQUEST_CHANGES review, reconstructs a run
dir with the **same branch** worktree, **seeded `sessions/`** (the original pi
session file), a mounted `review/` (report + decisions) as **binding authority**,
and a revision brief; runs the container with `--continue` from attempt 1 and a
revision directive; then **delivers on the same PR** (commit + push `origin/<branch>`,
PR comment, `Revised:` row — NO `gh pr create`, NO merge, NO task transition).
Added `Revised:`-row support to `bin/lib-pr-tracking.sh` and revise-mode tests to
`bin/test-implementer-driver.sh`.

## Story-by-story

### US1 — resolve + reconstruct ✅
**Done.** `--revise <pr>` parses the PR arg (URL / `owner/repo#num` / `repo#num` /
bare number), fetches PR metadata via `gh pr view`, guards open-and-unmerged
(else exit 2), derives the slug from the title `[factory] <slug>: …` (else exit
2), recovers the original impl session UUID from the task's `Raised by:
implementer run <uuid>` PR-tracking row, finds the newest
`docs/code-reviews/*-<slug>/` with a `REQUEST_CHANGES` verdict (else exit 2), and
reconstructs the run dir (same-branch worktree, seeded `sessions/`, mounted
`review/`, revision brief). Dry-run stops after reconstruction + a simulated pi
invocation.

**Evidence**: `resolve_pr_arg`, `pr_revision_metadata`, `resolve_revision_slug`,
`resolve_impl_session`, `resolve_review_report`, `resolve_revision`,
`prepare_revision_dir`, `write_revision_brief` in `bin/implementer-run.sh`.
Verified by Test 14 (dry-run smoke) + Test 15 (negatives → exit 2).

### US2 — continuation + revision directive ✅
**Done.** The pi invocation carries `--session-dir /sandbox/sessions --continue`
from **attempt 1** in revise mode (the seeded original session is the continuity
source), and the directive encodes the binding-authority rule ("fix EXACTLY what
the findings scope… WHERE THEY CONFLICT WITH YOUR EARLIER REASONING, THE FINDINGS
WIN. Resume your original implementation session context — do NOT restart from
scratch, do NOT re-litigate findings, do NOT expand scope… do NOT run any git
commands… do NOT change the task lifecycle").

**Evidence**: `run_container()` `sess_args` + revision `directive` branch.
Verified mechanically by Test 14: `--continue` + `--session-dir` appear in the
mock-podman log, co-occurring with the seeded session file (vacuous-guard test).

### US3 — delivery on the same PR ✅
**Done.** `deliver_revision()` commits the fix on the same branch, pushes
`origin/<branch>` (updating the open PR), posts a `gh pr comment` noting the
revision, and never calls `gh pr create`. Task stays `in-review` (no transition).

**Evidence**: `deliver_revision()` in `bin/implementer-run.sh`; the revise branch
of `main` (`main_revise()`) never calls `transition` or `push_and_pr`; `fail_run`
skips the `prd-ready` transition under revision (D3). Verified by Test 16:
origin branch advanced, PR comment posted, no `pr create`, task stays in-review.

### US4 — bookkeeping ✅
**Done.** `archive_revision()` writes the report to
`docs/implementations/<date>-<slug>/revision-<n>-report.md` (D5, same dir as v1
`report.md`); the SAME `IMPL_UUID` session file is extended and mirrored into
`docs/knowledge/sessions/<uuid>/` (+ index) by `finalize_revision_session()`;
`deliver_revision()` appends the decision-06 `Revised:` row; the run dir is
cleaned by the shared `cleanup_run_dir()`.

**Evidence**: `archive_revision`, `finalize_revision_session`,
`revision_number`/`REVISION_N` (stable, computed once in `prepare_revision_dir`).
Verified by Test 16: `revision-1-report.md` archived and `- Revised: …` row on
the task file.

### US5 — tests ✅
**Done.** `bin/test-implementer-driver.sh` gains revise-mode coverage:
(a) `--revise <pr> --dry-run` smoke — exit 0, run dir has seeded session +
mounted report + same branch + reuse of the original UUID, and `--continue` in
the simulated pi invocation (incl. a vacuous guard);
(b) non-dry smoke with mock `gh`/`podman` (via `IMPLEMENTER_PODMAN_BIN` /
`IMPLEMENTER_GH_BIN`) asserting same-branch push, no `pr create`, `Revised:`
row, task unchanged;
(c) negatives — closed/merged PR, unresolvable slug, and missing REQUEST_CHANGES
review each exit 2.

**Evidence**: Test 14/15/16 in `bin/test-implementer-driver.sh`, plus
`make_mock_gh_impl`, `make_mock_podman_impl`, `setup_revise_fixture` (bare
`origin` remote carrying master + PR branch). All 19 new assertions pass.

## File map (implemented)

- `bin/implementer-run.sh` — `--revise` arg; `podman_call`/`gh_call` seams;
  `IMPLEMENTER_RUNS_ROOT`/`IMPLEMENTER_ARCHIVES_ROOT` seams; `resolve_revision`,
  `prepare_revision_dir`, `write_revision_brief`, `archive_revision`,
  `deliver_revision`, `finalize_revision_session`, `main_revise`; revision
  directive in `run_container`; `REVISION_MODE` guard in `fail_run`.
- `bin/lib-pr-tracking.sh` — `pr_tracking_revised()` append-only `Revised:` row
  helper (and schema comment).
- `bin/test-implementer-driver.sh` — revise-mode fixtures + mocks + Test 14–16.

## Verification results (run inside /sandbox/worktree)

- **AC1** `bash -n bin/implementer-run.sh` → **OK (exit 0)**.
- **AC2** `bash bin/test-implementer-driver.sh` → **48 passed, 1 failed**. The
  single failure is the **known, pre-existing environmental wobble** the PRD
  explicitly acknowledges: `resolve_repo MANIFEST_BRANCH='master' — expected
  public-release`, caused by the gitignored
  `workspace-portability/workspace_restore_manifest.json` being absent from this
  bare worktree clone (fails identically at base before my changes). All 19 new
  revise-mode assertions pass.
- **AC3** Full sweep: `test-factory-run` **22/22** GREEN, `test-merge-pr` **8/8**
  GREEN, `test-transition-task` **45/45** GREEN, `test-review-driver` **60/61**
  (the 1 failure is the pre-existing `opensource/ponytail/skills` checkout
  absent in this bare clone — a gitignored host artifact, unrelated to this
  task's three changed files). No regression introduced.
- **AC4** `--revise <fixture-pr> --dry-run` exits 0 and the run dir proves: same
  branch checked out (`factory/demo/20260814-120000`), seeded `sessions/`
  containing the original session file, `review/` mounted with the
  REQUEST_CHANGES report + decisions, brief reuses the ORIGINAL impl UUID (no new
  UUID, D1), and `--continue` + `--session-dir` in the simulated pi invocation
  (Test 14).
- **AC5** Mock-gh log proves: push to the existing branch (remote branch advanced
  to a descendant), PR comment, **no `pr create`**, `Revised:` row on the task
  file, task stays `in-review` (Test 16).

## Decisions emerged

- `01-implementer-revision-test-seams.md` — added the `IMPLEMENTER_PODMAN_BIN` /
  `IMPLEMENTER_GH_BIN` seams and `IMPLEMENTER_RUNS_ROOT`/`ARCHIVES_ROOT` test
  seams as part of this task (D8: ponytail PR #2 seam not merged in this
  worktree), and compute `REVISION_N` once for a stable revision-report number.

## UAT hand-off list

- On a real host (with the gitignored `workspace_restore_manifest.json` and the
  live `opensource/` checkout present), confirm the full sweep is fully green:
  implementer (49), review (61), factory-run (22), merge-pr (8), transition (45).
  The two failures here are purely the absent gitignored host artifacts.
- First real use of the mode: run
  `bin/implementer-run.sh --revise <PR #2 implementer-ponytail> --dry-run` to
  inspect the reconstructed run dir (same branch, seeded session, mounted review),
  then the real run to amend PR #2 per `docs/code-reviews/2026-08-14-implementer-ponytail/report.md`.
- Confirm the live pi invocation in `run_container()` carries `--continue` +
  `--session-dir /sandbox/sessions` from attempt 1 on a real container, and that
  the revision directive's binding-authority wording reaches the model.
- Verify `gh pr comment` works on the host for the revision note, and that the
  branch push is a normal fast-forward on the already-open PR (no force).
- Review the `Revised:` row lands in the task PR-tracking section and that
  `revision-1-report.md` appears next to `report.md` in the SAME
  `docs/implementations/<date>-implementer-ponytail/` dir.
