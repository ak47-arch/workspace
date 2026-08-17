# Code Review

- Reviewed: https://github.com/ak47-arch/workspace/pull/10 (repo: ak47-arch/workspace, PR #10)
- Task: implementer-delivery-failure-loud · PRD: docs/prd-queue/2026-08-17-implementer-delivery-failure-loud.md · Review session: f28bb390-3980-46cd-956b-c3bcf33d9d4b
- Base: d556cafe0ca0e73d713a0d35a1b33b7370ae26cb → Head: bdac29e5483875fc1c5c41b8d5dea3f94d6db399

## Verdict

**APPROVE** — all 4 user stories implemented, scope fully contained to the PRD file map (2 files), the PRD acceptance command passes (72 passed, 0 failed), and the delivery-failure behavior (exit 1, clear FAILED reason, task reverted to prd-ready, no false "Done (exit 0)") is genuinely exercised and asserted. Only advisory findings — none correctness/scope/decision blocking.

## Verification results

| Command | Result | Evidence |
|---|---|---|
| `bash bin/test-implementer-driver.sh` (PRD acceptance command) | **72 passed, 0 failed** | `All tests passed.` Includes the two new delivery-failure blocks: push-fail (7 asserts: exit 1, `FAILED: delivery failed…`, no "Pushed branch", no "PR raised", no "Done (exit 0)", status→prd-ready, transition invoked) and pr-fail (9 asserts incl. branch present on the bare remote, `gh pr create` attempted). Full existing regression green (base had 62 pass-assertions, head 78). |
| `bash -n bin/implementer-run.sh` | passed | syntax OK |
| `bash -n bin/test-implementer-driver.sh` | passed | syntax OK |

Deferred (recorded, never skipped): a **real** non-dry successful delivery (live host push + real `gh pr create` against the live remote) requires network/GitHub credentials absent from this sandbox — same as the implementer's own report. The happy path is exercised via the non-dry `--revise` delivery (push to a real local bare remote) and the dry-run smoke; the PR-raising code is unchanged. Handed to UAT.

## Story-by-story

- **[PASS] US1 — push failure → non-zero exit + clear reason, no "Done (exit 0)"**: `bin/implementer-run.sh:656` `if ! git -C "$WORKTREE" push -u origin "$WORKTREE_BRANCH"; then echo "  ERROR: git push of branch … failed …"; return 1; fi`; `:1334` `if ! push_and_pr; then fail_run "delivery failed: branch push or PR creation"; fi`. `fail_run` prints `FAILED: …`, reverts task, exits 1 — so "Done (exit 0)." (line 1344) is unreachable. Push-fail test asserts exit 1, `FAILED:` present, no `Pushed branch`, no `Done (exit 0)`. Verified green.
- **[PASS] US2 — push ok but `gh pr create` fails → exit 1 + reason, branch left on remote**: `push_and_pr` returns 1 after 3 retry attempts when `pr_url` stays empty (`bin/implementer-run.sh:720`), leaving the pushed branch intact; the success-path guard routes it to `fail_run`. Pr-fail test asserts exit 1, `FAILED:` + reason, honest `Pushed branch` line, `gh pr create` attempted (mock `gh` via PATH), branch present on the bare remote, no `PR raised`, no `Done (exit 0)`. Verified green.
- **[PASS] US3 — on delivery failure task reverted to prd-ready (existing fail_run semantics)**: no new lifecycle machinery; `fail_run` (`bin/implementer-run.sh:793`) already does revert (`REVISION_MODE != true` → `transition "prd-ready"`), partial-report archive, and exit 1. Both delivery tests assert the mock `transition-task.sh` recorded `<prd-ready>` and the fixture task file reads `**Status**: prd-ready`. Verified green.
- **[PASS] US4 — successful delivery unchanged (host-authored commit, push, PR, exit 0)**: happy path untouched; `push_and_pr` still commits/pushes/raises PR tagged `factory:needs-review`; dry-run still returns 0 before the gh path. Regression suite (incl. dry-run smoke + non-dry `--revise` delivery) all green.

## Deterministic checks

- **[PASS] D1 — PR metadata sane**: head `bdac29e "implementer(implementer-delivery-failure-loud): run 8370f85b…[factory]"`, base `d556caf` both resolve; single-commit PR; diff non-empty and scoped to exactly the 2 PRD-mapped files (220 insertions / 5 deletions).
- **[PASS] D2 — Worktree clean / read-only**: `git status --short` clean at start and at finish; detached HEAD at `bdac29e`; no reviewer mutations.
- **[PASS] D3 — Scope containment**: only `bin/implementer-run.sh` and `bin/test-implementer-driver.sh` changed — exactly the PRD file map. No out-of-scope files, no stray deps (no package/gem/requirements/glock changed). The `setup_fixture` manifest fallback in the test file is a legitimate in-file robustness fix (resolves the pre-existing manifest-dependent test failure).
- **[PASS] D4 — Scope ⊆ PRD file-map**: both PRD-mapped files present in the diff; nothing promised missing. Untouched files (`review-run.sh`, `factory-run.sh`, `transition-task.sh`, configs, factory.yml) confirmed not modified.
- **[PASS] D5 — Story → diff coverage**: US1→push guard + success-path guard; US2→push_and_pr return + pr-fail test; US3→fail_run (unchanged) + tests; US4→regression green. No diff capability without a story. (Minor: the test's `setup_fixture` manifest fallback is not tied to a US but is test-infra support for the new full-main tests — acceptable.)
- **[PASS] D6 — No secrets / stray deps**: diff scan clean — only `OPENROUTER_API_KEY` config references and a fake `sk-test` test key; no credentials/`.env`/private keys; no new dependencies.
- **[PASS] D7 — Implementer report matches actual diff** (partial, advisory): core claims (push guard, success-path guard, `fail_run`, both delivery tests, all-green run) match the diff and reproduce. **Two claims do NOT match the final code** (see Advisory A1): the report/decision claim `push_and_pr` routes delivery gh through the `gh_call`/`IMPLEMENTER_GH_BIN` seam, but the diff leaves raw `gh`; the test instead injects a mock `gh` on `PATH`. The report's archived test count (71) is also one below the actual current run (72).

## Judgment checks

- **[PASS] J1 — Story intent**: observable behavior holds. The `if ! push_and_pr` guard is explicitly needed under `set -e` (an unguarded failing call would abort before `fail_run`), and `push_and_pr` now surfaces push/PR failure explicitly (truthfulness: "Pushed branch"/"PR raised" only printed on success). Verified by full-non-dry runs against mock podman/gh/bare-remote fixtures.
- **[PASS] J2 — PRD-decision conformance** (one divergence, advisory): fix in `implementer-run.sh` only, uses existing `fail_run`, explicit guard placement — all as the PRD's implementation decisions dictate. **Divergence**: the implementer's own recorded decision D01 (route delivery gh through the `IMPLEMENTER_GH_BIN` seam) was NOT implemented — `push_and_pr` still calls raw `gh`; the failing-PR test instead injects a mock `gh` on `PATH`. Functionally equivalent and the failing-PR story is genuinely tested, so this does not block, but the recorded decision and report do not reflect the final code.
- **[PASS] J3 — Edge / error paths**: `gh` not installed → `command -v gh` returns 1 → routes to `fail_run` (loud, no swallow). Push failure → explicit ERROR + return 1 (no misleading "Pushed branch"). PR failure after 3 retries → ERROR + return 1 (branch remains pushed, honest). Under `set -euo pipefail`, the `if !` guard protects `fail_run` from being pre-empted. `pr_url` is bound (`local attempt=0 pr_url=""`), so the bash-5.2 `set -u` unbound-variable abort is avoided on the failure path.
- **[PASS] J4 — Ponytail over-engineering pass (ultra)**: ponytail skills were not present in this container (the six `opensource/ponytail/skills` are injected by the host driver and were not available read-only here); the review-ops reference documents them as host-injected. I applied the ponytail methodology manually over the diff. The driver changes are the minimum for the behavior (no yagni/delete findings). The test additions (~205 lines) are the necessary scaffolding for full-non-dry delivery-failure runs; the only advisory is the duplication of the two assertion blocks (see Advisory A2). No new `ponytail:` debt markers introduced.
- **[PASS] J5 — UAT gaps**: enumerated in the hand-off list (real non-dry live delivery not runnable in sandbox; branch-is-left-on-remote + FAILED-reason real run; happy-path regression on the live remote).

## Findings

### Blocking (→ REQUEST_CHANGES)
- None.

### Advisory (consider / over-engineering)
- **A1** `docs/implementations/2026-08-17-implementer-delivery-failure-loud/decisions/01-delivery-failure-loud-gh-seam.md` + `report.md` "Note": recorded/accepted decision D01 and the report claim `push_and_pr` uses the `gh_call`/`IMPLEMENTER_GH_BIN` seam, but the actual diff leaves raw `gh` and the test injects a mock `gh` on `PATH` instead. The behavior is functionally correct and the failing-PR story is genuinely tested — this is a report/decision-accuracy issue, not a correctness one. Recommend either updating the decision/report to describe the PATH-injection approach actually used, or (if the seam is preferred) applying the D01 change. Net: 0 behavior change required for approval.
- **A2** `bin/test-implementer-driver.sh` (delivery-failure block): the push-fail and pr-fail blocks are ~90% duplicated assertions. `shrink` — could extract a shared `assert_delivery_failure <mode>` helper. Purely stylistic; the verbatim assertions improve per-mode readability, so acceptable as-is.
- **A3** `docs/implementations/…/report.md`: reported `71 passed` vs actual `72` in the current head run (off by one — one assertion added after the report was written). Non-blocking.

## Ponytail debt (harvested from changed files)

No `ponytail:` debt markers in the changed files (`grep -rnE '(#|//) ?ponytail:'` over `bin/implementer-run.sh` and `bin/test-implementer-driver.sh` → none). Clean ledger.

## UAT hand-off list

1. **Real non-dry successful delivery (required)**: confirm one real driver run still delivers normally on the live remote — host-authored commit, push, PR raised tagged `factory:needs-review`, exit 0 (Story 4). Not runnable here (no network/GitHub creds).
2. **Real push-succeeds-but-PR-fails run**: confirm a real run where `gh pr create` fails leaves the branch on `origin`, prints `FAILED: delivery failed: branch push or PR creation`, reverts the task to `prd-ready`, and exits non-zero (Story 2) — and that re-run guidance applies to the leftover branch.
3. **Real push-failure run**: confirm a real failed branch push prints the `ERROR: git push … failed` line and routes to the failure path (Story 1).
4. **Decision/report hygiene (advisory)**: before next iteration, align `decisions/01-delivery-failure-loud-gh-seam.md` and `report.md` with the actual implementation (PATH-injected `gh` mock, not the `gh_call` seam) — the divergence is cosmetic but will confuse future maintainers.
5. **`set -u` robustness re-check on the host**: the delivery-failure path was run under bash 5.2 here; confirm `local pr_url` binding behaves the same on the host's bash version during a live failing delivery.
6. **Advisory (non-blocking)**: consider the `shrink` refactor of the two duplicated delivery-failure assertion blocks (A2).
