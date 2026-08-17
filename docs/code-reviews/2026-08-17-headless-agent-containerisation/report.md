# Code Review
- Reviewed: https://github.com/ak47-arch/workspace/pull/6 (repo: ak47-arch/workspace, PR #6)
- Task: headless-agent-containerisation · PRD: docs/prd-queue/2026-08-17-headless-agent-containerisation.md · Review session: 3133f888-637f-4d83-99f1-f94b88a08328
- Base: 79ff1704342b6bea9ea46b75aef713200d161acb → Head: 321c1271cda1d2772b7f137f0a8edcaf28dde7a2

## Verdict
APPROVE — implements all 6 user stories and decisions 01–04 faithfully; 40/40 unit tests pass, dry-run wiring verified, no blocking findings, no secrets, scope contained. Real CI is deferred (external infra/secrets) and left to UAT.

## Verification results
- **`bash bin/test-factory-run.sh`** — RAN (exit 0). Evidence: "factory-run: 40 passed, 0 failed / All tests passed." Confirms: headless flag + dry-run skip, APPROVE-first (1 review, no revise), gate-skip under non-interactive stdin, REQUEST_CHANGES→revise→APPROVE (1 revise / 2 reviews), cap exhaustion REVISION_CAP=2 (exit 1, exactly 2 revises, "cap exhausted" surfaced), REVISION_CAP=0 (no revise, exit 1), empty/partial verdict (no revise, report surfaced), missing archived report (exit 1 "Verdict unavailable"), authority split (never touches merge).
- **`FACTORY_WORKSPACE=<fixture> bin/factory-run.sh --headless --dry-run`** — RAN (exit 0) against a fixture workspace with a stub implementer. Evidence: Stage 1 runs `--dry-run`, prints "[dry-run] no PR exists — review stage skipped", exits 0. Loop wiring proven without real drivers/containers.
- **Real end-to-end (workflow_dispatch → PR raised + review posted + task in-review)** — DEFERRED. Requires GitHub-hosted runner, `docker build` of `sandbox:latest` from `workspace-portability/container`, `gh auth` with cross-repo PAT, and repo secrets (`FACTORY_GH_PAT`, `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_BASE_URL`) — none available in this sandbox. Reviewed statically (workflow YAML, docker seam, gate logic, digest of driver contracts) and listed in UAT hand-off.

## Story-by-story
- [PASS] US1 Auto-start on pushed Final PRD + prd-ready task — `.github/workflows/factory.yml`: `on: push paths: ['docs/prd-queue/**.md']`; "Status gate + resolve task slug" step greps `**Status**: Final` on the PRD and `**Status**: prd-ready` on `docs/tasks/<slug>.md`; exits 0 silently when nothing ready.
- [PASS] US2 No interactive input — `bin/factory-run.sh` `--headless` skips the UAT gate (`if [ "$HEADLESS" != true ] && [ "$YES" != true ]`); test `outH2` proves `< /dev/null` (no stdin) still completes with "APPROVED".
- [PASS] US3 REQUEST_CHANGES auto-revise + re-review up to cap — `headless_loop()` runs `implementer-run.sh --revise "$PR_ARG"` then re-reviews up to `REVISION_CAP` (default 3, env-configurable); tests H3 (1 revise / 2 reviews) and H4 (REVISION_CAP=2) pass.
- [PASS] US4 APPROVE → stop, merge-ready PR, task in-review — headless APPROVE branch `exit 0`; test H1 (single review, no revise). PR raise/label/post (factory:needs-review / reviewed-ok|review-blocked) and the `in-progress → in-review` transition are performed by the (untouched) implementer/reviewer drivers; loop wiring verified here, live run deferred.
- [PASS] US5 Cap exhausted → fail with last report surfaced — `headless_loop` cap branch calls `surface_report()` then `exit 1`; tests H4 ("cap exhausted") and H5 (REVISION_CAP=0 → no revise, exit 1) pass.
- [PASS] US6 Merge not part of pipeline — no merge path in `factory-run.sh` or `factory.yml`; the suite's "authority split: chain never touches merge" test passes; `bin/merge-pr.sh` is referenced only as operator guidance text.

## Deterministic checks
- [PASS] D1 PR metadata sane — head commit `321c127 implementer(headless-agent-containerisation): run 771b4017-… [factory]` is a well-formed factory implementer commit; base/head refs exist; diff non-empty (4 files, +368/−17).
- [PASS] D2 Worktree clean / read-only — `git status` clean, HEAD detached at head ref; reviewer made no changes during the run.
- [PASS] D3 Scope containment — diff touches exactly: `.github/workflows/factory.yml` (new, PRD map), `bin/factory-run.sh` (PRD map), `bin/test-factory-run.sh` (PRD map), `.gitignore` (+2 lines). `.gitignore` is not in the PRD file-tree but is a **necessary enabling change**: `.github/` is globally ignored (line 34) and without `!.github/` (line 36) the new workflow would never be tracked (confirmed `git ls-files .github/workflows/factory.yml`; only that one file lives under `.github/`, so re-tracking has no collateral). Justified, noted advisory. No unrelated refactors, no stray deps.
- [PASS] D4 Scope ⊆ PRD file-map — all three implementation files in the PRD map are present in the diff; `.gitignore` is the only sanitised-enabling addition. `docs/tasks/headless-agent-containerisation.md` and `docs/knowledge/sessions/01a00c50…/decisions/` correctly belong to the base (planning) commit, not this PR.
- [PASS] D5 Story → diff coverage — each of US1–US6 maps to concrete hunks/files (see story-by-story). No diff capability exists without a story asking for it.
- [PASS] D6 No secrets / stray deps — diff scan found no committed credentials/keys/.env; secrets referenced only as `${{ secrets.* }}`. No new dependencies (no package/requirements changes).
- [PASS*] D7 Implementer report matches diff — the archived report `docs/implementations/2026-08-17-headless-agent-containerisation/report.md` is **not present** in the worktree/git, so no formal report↔diff comparison is possible. The diff itself was verified in D3–D5 to match the claimed scope (all implementation files present, stories covered, nothing dropped). Marked PASS with the archive-absence caveat surfaced in UAT.

## Judgment checks
- [PASS] J1 Story intent — observable behaviour of every story would hold: push→CI gate, no-input loop, auto-revise loop, APPROVE stop, cap-fail surface, merge excluded. Proven mechanically by the 40-test suite plus the fixture dry-run.
- [PASS] J2 PRD-decision conformance — d01 (backend host; no herdr/Woodpecker built), d02 (merge-ready PR; merge excluded), d03 (GHA fast path; `IMPLEMENTER_PODMAN_BIN=docker` seam, image built in-job, ghcr publishing deferred), d04 (`--headless` loop, cap default 3 env-config, verdict read-back via `grep -m1 '^APPROVE\|^REQUEST_CHANGES'` on `docs/code-reviews/<date>-<slug>/report.md`, "do NOT assume line 1", empty verdict ⇒ surface + exit non-zero + NO revise). All honored exactly.
- [PASS] J3 Edge / error paths — handled and tested: empty/partial verdict (PARTIAL stub), missing archived report ("Verdict unavailable", exit 1), REVISION_CAP=0 (no infinite loop), reviewer failure (exit 2), implementer + revision failure (exit 1), non-interactive stdin (gate-skip/EOF defer), ambiguous `--pick` (slug resolved from implementer's `Task PR tracking: … on docs/tasks/<slug>.md` line — confirmed this string is emitted by `implementer-run.sh` line ~709).
- [PASS] J4 Ponytail over-engineering (advisory, ultra) — Lean, matches contract with no speculative abstraction. One minor `shrink` advisory (duplicate slug resolution, below). No YAGNI/dependency bloat. Real CI docker/gh steps are required, not speculative.
- [PASS] J5 UAT gaps — real end-to-end and infra-dependent items listed in hand-off; nothing unverifiable was silently claimed as passed.

## Findings
### Blocking (→ REQUEST_CHANGES)
- None.

### Advisory (consider / over-engineering)
- `bin/factory-run.sh:L135-137` / `L257-259` — `shrink`: the slug-from-$RUN_LOG resolution block (`grep -oE 'docs/tasks/[^ ]+\.md' "$RUN_LOG" …`) is duplicated (pre-gate for PR_ARG, and again in the headless entry). Extract a 3-line `resolve_slug()` helper and call it in both spots. Cosmetic; never alone blocking.
- `.gitignore:L34,36` / `.github/workflows/factory.yml` — `yagni(note)`: un-ignoring the whole `.github/` dir to track one workflow is the minimal mechanical fix; acceptable because `.github/` currently holds only that file. Confirm no future `.github` engine files are unintentionally tracked. Advisory only.

## Ponytail debt (harvested from changed files)
- No `ponytail:` shortcut markers in `bin/factory-run.sh`, `bin/test-factory-run.sh`, `.github/workflows/factory.yml`, or `.gitignore`. No debt.

## UAT hand-off list
1. **Real end-to-end (workflow_dispatch)** with a genuine `**Status**: Final` PRD + `prd-ready` task → confirm: PR raised + labelled `factory:needs-review`, review report posted, task at `in-review`, merge-ready PR. **Precondition**: repo secrets `FACTORY_GH_PAT`, `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_BASE_URL` configured first.
2. Confirm `docker build -t sandbox:latest workspace-portability/container` succeeds on `ubuntu-latest` and that the `IMPLEMENTER_PODMAN_BIN=docker` seam is flag-compatible with the driver's podman calls (`run --rm --network=host --env-file -v --name`, `rm -f`, `stop -t`, `ps --format`).
3. Confirm the repo_map checkout clones `workspace-portability` (and all targets) into `$GITHUB_WORKSPACE` so `docker build workspace-portability/container` resolves and the driver's `$WORKSPACE/$TARGET_REPO` git resolution finds repos.
4. Confirm `gh auth login --with-token` + `gh auth setup-git` with `FACTORY_GH_PAT` enables cross-repo `git push` and `gh pr create/comment/label` inside the runner (GITHUB_TOKEN is single-repo).
5. Confirm cap-exhaustion behaviour in real CI: 3 REQUEST_CHANGES → run fails non-zero with the last review report surfaced (no revise past cap).
6. Verify merge exclusion live: nothing in the workflow/loop pushes master; run `bin/merge-pr.sh` yourself after your UAT (decisions 02/05/07).
7. Confirm no re-trigger loop: task/decision tracking commits to master don't touch `docs/prd-queue/**.md`, so the `paths` filter does not re-fire the workflow mid-loop.
8. Verify the `--pick` (ambiguous) headless fallback resolves the slug from the implementer's `Task PR tracking: … on docs/tasks/<slug>.md` RUN_LOG line (single-ready `--task` path is already proven).
9. **Observation**: the implementer's archived report for this task (`docs/implementations/2026-08-17-headless-agent-containerisation/report.md`) was not present in the worktree/git at review time — confirm it is archived/pushed for auditability.
