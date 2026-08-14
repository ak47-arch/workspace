# Code Review
- Reviewed: ak47-arch/workspace#3 (repo: ak47-arch/workspace, PR #3)
- Task: implementer-revision-mode · PRD: docs/prd-queue/2026-08-14-implementer-revision-mode.md · Review session: a15ea23c-29dd-4762-a620-49dda5f3cdcc
- Base: bb2b5e12572481092e9c430d11dac1c6371d9df0 → Head: 223b2bde8ed28c3e36f81228862a128eedf9fbfe

## Verdict
APPROVE — all five user stories implemented and mechanically verified; the single test-suite failure is the PRD-acknowledged pre-existing environmental wobble (gitignored `workspace_restore_manifest.json` absent from the bare worktree), not a regression. Remaining findings are advisory (dead code, duplicated helper, shebang hygiene) and never alone block.

## Verification results
All commands run inside `/sandbox/worktree` (read-only except for the ephemeral fixture dirs the test suite creates in `mktemp` dirs). No git state in the worktree was mutated; `git status` stayed clean.

- **AC1 — `bash -n bin/implementer-run.sh`** → **RAN, exit 0** (syntax OK). Also `bash -n bin/lib-pr-tracking.sh` and `bash -n bin/test-implementer-driver.sh` both exit 0. `shellcheck` not installed in container (deferred, recorded).
- **AC2 — `bash bin/test-implementer-driver.sh`** → **RAN, exit 1: 48 passed, 1 failed**. The only failure is `resolve_repo MANIFEST_BRANCH='master' — expected public-release`. Evidence this is the PRD-flagged pre-existing wobble: `workspace-portability/workspace_restore_manifest.json` is untracked at both base and head (`git ls-files` empty, `git show <base>:<path>` → fatal), and the real `/workspace/workspace-portability/workspace_restore_manifest.json` exists only outside the bare worktree. **All 19 new revise-mode assertions pass** (Tests 14/15/16, incl. dry-run smoke, negatives → exit 2, non-dry delivery).
- **AC3 — full sweep** → **RAN; all GREEN except the known implementer wobble**: review-driver **61/61**, factory-run **22/22**, merge-pr **8/8**, transition-task **45/45**, implementer **48/49** (same manifest wobble). Matches the implementer's archive claims.
- **AC4 — `--revise <fixture> --dry-run`** → **RAN via Test 14, exit 0**; run dir proves same branch checked out (`factory/demo/20260814-120000`), `sessions/` seeded with original session file, `review/` mounted (REQUEST_CHANGES report + decisions), brief reuses the ORIGINAL impl UUID (no new UUID, D1), `--continue` + `--session-dir` in the simulated pi invocation (incl. the vacuous guard).
- **AC5 — mock-gh non-dry delivery** → **RAN via Test 16, exit 0**; proves same-branch push (remote branch advanced to a descendant of original head), `gh pr comment` posted, **no `gh pr create`**, `Revised:` row appended, task stays `in-review`, `revision-1-report.md` archived next to v1 (D5).
- **Deferred (not runnable headless)**: real podman container run (no runtime in container), real `gh` calls (no credentials / driver-owned), and the gitignored-host-artifact scenarios. Recorded for UAT.

## Story-by-story
- [PASS] **US1 — resolve + reconstruct** — `resolve_revision` (`resolve_pr_arg` → `pr_revision_metadata` → `resolve_revision_slug` → `resolve_impl_session` → `resolve_review_report` → PRD lookup) + `prepare_revision_dir`/`write_revision_brief` in `bin/implementer-run.sh`. Errors exit 2 (merged PR, unresolvable slug, missing REQUEST_CHANGES review) — Test 15 confirms all three. Dry-run stops after reconstruction + simulated pi invocation — Test 14.
- [PASS] **US2 — continuation + revision directive** — `run_container` sets `sess_args+=(--continue)` from attempt 1 when `REVISION_MODE=true`, and the revision `directive` encodes binding-authority ("WHERE THEY CONFLICT WITH YOUR EARLIER REASONING, THE FINDINGS WIN"; no restart/re-litigate/scope-expansion; no git; no lifecycle change). Verified mechanically (Test 14: `--continue` + `--session-dir` in the log co-occurring with the seeded session — the vacuous guard).
- [PASS] **US3 — delivery on the same PR** — `deliver_revision` commits + pushes `origin/<branch>` (updates PR #N), posts PR comment, and never calls `gh pr create`; `main_revise` never calls `transition` or `push_and_pr`; `fail_run` skips `prd-ready` under revision (D3). Test 16 asserts origin-head advanced + `pr comment` present + `<create` absent + task stays `in-review`.
- [PASS] **US4 — bookkeeping** — `archive_revision` writes `revision-<n>-report.md` next to v1 (D5, via `revision_number`); `finalize_revision_session` extends the SAME `IMPL_UUID` session dir + index; `deliver_revision` appends the decision-06 `Revised:` row; shared `cleanup_run_dir` (durable kept). Test 16 confirms the archive + `Revised:` row.
- [PASS] **US5 — tests** — Test 14/15/16 added with fixtures (`setup_revise_fixture`), mocks (`make_mock_gh_impl`, `make_mock_podman_impl`), positive + negatives + vacuous guard. All pass on this checkout (aside from the unrelated pre-existing manifest wobble).

## Deterministic checks
- [PASS] **D1 — PR metadata sane** — branch `factory/implementer-revision-mode`, head 223b2bde, commit `implementer(implementer-revision-mode): run cb6a90c1-... [factory]`; base/head exist; diff non-empty and scoped (3 files, +836/−17).
- [PASS] **D2 — worktree clean / read-only** — `git status` clean on the PR head throughout; reviewer made no changes (`git status` re-verified clean after runs).
- [PASS] **D3 — scope containment** — changed files are exactly `bin/implementer-run.sh`, `bin/lib-pr-tracking.sh`, `bin/test-implementer-driver.sh` — all inside the PRD file map. No stray deps (no requirements/gems/package changes).
- [PASS] **D4 — scope ⊆ PRD file-map** — all three file-map entries are present in the diff; the "Bookkeeping (via transition tooling)" doc-file entries are driver-side post-merge (per PRD D3 note), correctly absent from this diff.
- [PASS] **D5 — story → diff coverage** — each US maps to concrete hunks (see story-by-story); no out-of-diff capability that no story asks for.
- [PASS] **D6 — no secrets / stray deps** — no credentials, keys, or `.env` in the diff; no new dependencies added (the `gh_call`/`podman_call` seams resolve to existing binaries).
- [PASS] **D7 — implementer report matches diff** — `docs/implementations/2026-08-14-implementer-revision-mode/report.md` claims all five stories + file map; I confirmed each named function/fixture exists in the diff and each verification claim is reproduced by my own runs.

## Judgment checks
- [PASS] **J1 — story intent** — the observable behavior each story describes actually holds under the tests: reconstruction (US1), continuity + binding directive (US2), same-PR delivery with no new PR (US3), bookkeeping (US4). Intent, not just wording, is satisfied.
- [PASS] **J2 — PRD-decision conformance** — D1 reused original UUID (no `new_uuid` in revise path); D2 binding-authority directive present; D3 no task transition (both `fail_run` guard and `main_revise` skip `transition`); D4 no `pr create`/no merge; D5 same-dir archive; D6 session seed named `<ts>_<uuid>.jsonl`; D7 `--resume` left reserved; D8 seam added as `IMPLEMENTER_PODMAN_BIN` (ponytail PR #2 had not merged in this worktree, so adding the seam here is per D8).
- [PASS] **J3 — edge/error paths** — closed/merged PR → exit 2; unresolvable slug → exit 2; missing REQUEST_CHANGES review → exit 2; missing original session file warns but continues (guarded); missing review report gracefully skips comment body; `gh` absent → warn + skip comment. All covered.
- [PASS] **J4 — Ponytail over-engineering pass (ultra)** — see advisory findings below. Two duplication/dead-code findings; none blocking.
- [PASS] **J5 — UAT gaps** — listed in UAT hand-off below.

## Findings
### Blocking (→ REQUEST_CHANGES)
- None.

### Advisory (consider / over-engineering)
- `bin/lib-pr-tracking.sh`:38 — `L~38: yagni dead helper. pr_tracking_revised() is defined but never called — deliver_revision inlines the same ensure/has/add + \"Revised: ...\" echo. Delete pr_tracking_revised (and tighten the schema comment only where needed).`
- `bin/implementer-run.sh`:~1040 — `L~1040: shrink duplicate. finalize_revision_session() reimplements append_decisions_to_index() (~40 lines: cp outbox decisions→sess_dir, ensure `### $PROJECT` section, python index-insert, sorter) almost verbatim. Replace the body with a call to append_decisions_to_index()` (IMPL_UUID is the same original UUID in revise mode, so sess_dir is identical), keeping only the decision-mirror/session-extension that differs.
- `bin/test-implementer-driver.sh`:1 — `L1: hygiene. A blank line was added before `#!/usr/bin/env bash`, so direct `./bin/test-implementer-driver.sh` execution would fail (shebang must be line 1). Works under `bash script` invocation, but remove the leading blank line for robustness.`
- `bin/implementer-run.sh`:~730 — `L~730: shrink minor. PR_HEAD_SHA (headRefOid) is fetched in pr_revision_metadata() but never used — prepare_revision_dir checks out by branch name. Drop the unused field unless it is meant to guard the no-op delivery.`

## Ponytail debt (harvested from changed files)
- No `ponytail:` shortcut markers in `bin/implementer-run.sh`, `bin/lib-pr-tracking.sh`, or `bin/test-implementer-driver.sh`. (The two duplication/dead-code advisory findings above are the closest thing to deferral debt and are not marked with markers.)

## UAT hand-off list
1. **First real use of the mode** — run `bin/implementer-run.sh --revise <PR #2 implementer-ponytail> --dry-run` on a real host to inspect the reconstructed run dir (same branch, seeded session, mounted review), then a real run to amend PR #2 per `docs/code-reviews/2026-08-14-implementer-ponytail/report.md`. Confirm the `Revised:` row and `revision-1-report.md` land next to v1 in the SAME `docs/implementations/<date>-implementer-ponytail/`.
2. **Full implementer suite on a real host** — with the gitignored `workspace_restore_manifest.json` present, confirm the implementer suite is fully green (49/49; the 48/49 here is solely the absent manifest). All other suites already verified green (review 61, factory-run 22, merge-pr 8, transition 45).
3. **Real container continuity** — confirm the live pi invocation in `run_container()` carries `--continue` + `--session-dir /sandbox/sessions` from attempt 1 on a real container, and that the revision directive's binding-authority wording reaches the model.
4. **Real delivery mechanics** — confirm `gh pr comment` works on the host for the revision note, and that the branch push is a normal fast-forward on the already-open PR (no force push). Confirm no `gh pr create` is ever invoked and the task stays `in-review` through the re-review.
5. **Decision-06 row sanity** — verify the `Revised:` row format `- Revised: <head-sha> (<ts>, impl session <uuid>, addressing review <r-session>)` reads correctly and that re-running a revision is idempotent (no duplicate rows for the same head SHA).
