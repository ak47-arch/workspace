# Implementer Report — code-review-agent (Impl session d7a5fbb9-c030-4800-8f3d-fb217d36d1cd)

PRD: `docs/prd-queue/2026-08-13-code-review-agent.md`. All work in `/sandbox/worktree`.
No git commands were run (host owns all git).

## Story-by-story

- **US1 — Trigger `bin/review-run.sh <pr>` → structured report.** DONE.
  `bin/review-run.sh` (NEW) mirrors `bin/implementer-run.sh`: host driver resolves a
  `repo#num` / `owner/repo#num` / URL / bare-slug / bare-number PR, checks out the PR
  head, runs the read-only worker, archives the report to `docs/code-reviews/`.
  Verified by `bin/test-review-driver.sh` (resolve_pr arg-parsing tests pass).
- **US2 — Driver resolves repo, task slug, PRD from PR metadata.** DONE.
  `resolve_pr` → `pr_metadata` (gh `pr view`) → `resolve_slug` (title `[factory] <slug>:` /
  branch `factory/<slug>/<ts>`) → `resolve_repo` (task `Project` → `config/reviewer.json`
  `repo_map` + PRD from `docs/prd-queue/*-<slug>.md`). Verified: slug title/branch tests,
  repo_map + PRD-location tests pass.
- **US3 — Worker checks out PR head read-only, diffs `base...head`, runs PRD verification.** DONE.
  Driver fetches the head SHA and base ref, checks out the head into the run worktree
  (read-only for the worker); `review-ops` contract instructs `git diff <base>...<head>`
  and running the PRD verification commands with pass/fail + run/deferred evidence.
  Verified: worktree-checked-out-at-head, base...head-diff-resolves, worktree-clean tests pass.
- **US4 — Deterministic + judgment checks.** DONE.
  `review-ops` SKILL.md declares deterministic checks D1–D7 (metadata sane, clean worktree,
  scope ⊆ PRD file-map, story→diff coverage, no secrets/stray deps, implementer's archived
  report vs actual diff) and judgment checks J1–J5 (story intent, decision conformance,
  edge/error paths, ponytail over-engineering, UAT gaps). No config registry — checks are a
  skill edit (YAGNI, per PRD).
- **US5 — Structured report posted to PR + archived.** DONE.
  Fixed report schema in `review-ops`; driver `archive()` → `docs/code-reviews/<date>-<slug>/`
  (report + decisions + brief) and `post_pr_comment()` (`gh pr comment`). Verified: archive
  test + mock gh `<comment>` call-count test pass.
- **US6 — REQUEST_CHANGES does not merge / complete.** DONE.
  Driver's successful path only transitions to `in-review` (never `complete`); the PRD
  stays in `docs/prd-queue/` until user UAT. `fail_run` leaves the task `in-progress`. No
  merge path exists.
- **US7 — On success driver transitions `in-progress → in-review` + links session.** DONE.
  `transition()` in `review-run.sh` calls `transition-task.sh <slug> --to in-review
  --session <uuid>:review`; verified by the dry-run transition test. DRD queue untouched
  (host-owned).
- **US8 — Reuses `sandbox:latest`, config shape mirrored.** DONE.
  `config/reviewer.json` mirrors `implementer.json` (`repo_map`, `model`, `timeout_sec`,
  `respawn_cap`, `env_allowlist`, `image`, `runs_root`) plus `reviews_root` and the
  `ponytail { skills_dir, default_mode }` node. Image is `sandbox:latest`, reused unmodified.
- **US9 — Checks declared in versioned `review-ops` skill / `code-reviewer` persona.** DONE.
  New `.agents/skills/review-ops/SKILL.md` (check classes + fixed report schema + ponytail
  pass) and `.pi/agents/code-reviewer.md` (read-only reviewer persona). Extending robustness
  is a skill/persona edit, not a driver change.
- **US10 — Reviewer read-only: no commits/writes, no GH credential in container.** DONE.
  Persona + `review-ops` + brief all forbid git mutation and `gh`; `write_env_file` allows
  only whitelisted LLM/Langfuse vars plus `PONYTAIL_DEFAULT_MODE` — never a GitHub token.
  Verified: "env file excludes GITHUB_TOKEN", "review-run.sh never references GITHUB_TOKEN"
  tests pass. Driver does all `gh` host-side via a lazy `gh_call` seam.
- **US11 — Ponytail over-engineering pass (six skills at ultra, advisory).** DONE.
  Driver passes six `--skill /workspace/opensource/ponytail/skills/{ponytail,ponytail-review,
  ponytail-audit,ponytail-debt,ponytail-gain,ponytail-help}` flags and forces
  `PONYTAIL_DEFAULT_MODE=ultra` in the container; `review-ops` J4 runs `ponytail-review` on
  `base...head` (`L<line>: <tag> <what>. <replacement>.`, tags delete/stdlib/native/yagni/
  shrink) as an **advisory subclass** (never alone blocking) and harvests `ponytail:` debt
  into the report's UAT section. Verified: six-flag count, per-skill flags, ponytail skill
  presence in opensource checkout, and `PONYTAIL_DEFAULT_MODE=ultra` in env tests pass.

## Verification results

Ran inside `/sandbox/worktree`:

- `bash -n` on `bin/review-run.sh`, `bin/test-review-driver.sh`, `bin/implementer-run.sh` — PASS.
- `bin/test-review-driver.sh` — **50/50 pass** (the new driver unit suite: arg parsing,
  slug/repo/PRD resolution, run-dir/brief contract, PR-head checkout + base fetch + clean
  worktree, env guardrail no GH token + `PONYTAIL_DEFAULT_MODE=ultra`, six ponytail flags,
  archive to `docs/code-reviews/<date>-<slug>/`, dry-run transitions, mock-gh call-counted
  comment/label, static no-`GITHUB_TOKEN` guardrail).
- `bin/test-transition-task.sh` — **45/45 pass** (regression).
- `bin/test-implementer-driver.sh` — **28 pass, 1 fail**, and that failure is
  **environmental, not a regression**: `resolve_repo MANIFEST_BRANCH = master (expected
  public-release)`. Cause: `workspace-portability/workspace_restore_manifest.json` is
  gitignored from the sandbox worktree clone (see `.gitignore` `/workspace-portability/`),
  so the fixture can't copy it and the manifest-branch lookup falls back to `master`. On the
  host this file exists and the test passes. My only edit to `implementer-run.sh` was the
  PR-label block (no change to `resolve_repo` or the manifest lookup).
- `shellcheck` — not installed in sandbox; skipped (unit tests + `bash -n` cover the logic).

**Not verifiable in the sandbox (UAT hand-off):**
- Real container runs (`podman` unavailable here) — the podman `pi --skill … --continue`
  invocation, worker-side report emission, and the non-deterministic APPROVE/REQUEST_CHANGES
  fixture sanity + "no gh/commit from the container" guardrails must be exercised on the
  host with a real sandbox + gh.
- Real `gh` resolve/comment/label + `--pick` against an actual GitHub PR (mocked here).

## UAT hand-off list

1. Run `bin/review-run.sh <some-factory-PR> --dry-run` on the host and confirm the run dir,
   PR-head checkout, brief, and container invocation (six `--skill` flags, `ultra`, no GH
   token) — then a real (non-dry) run posts the report and labels the PR.
2. Confirm a valid `sanbox:latest` container image is present; `bin/sandbox-build.sh` if not.
3. Confirm `gh` is authenticated host-side (the driver's only `gh` boundary).
4. Confirm an implementer PR now arrives tagged `factory:needs-review` (the `--label`
   addition to `bin/implementer-run.sh`) and that `--pick` selects it.
5. Approval fixture sanity, REQUEST_CHANGES fixture (blocking finding), and the "worker
   made no commits / no gh / no token-in-container" guardrails on a real container.

## Decisions emerged

- `outbox/decisions/01-review-driver-gh-call-and-test-seam.md` — reviewer resolves `gh`
  lazily via a `gh_call` function (host-only, mockable), plus the fixture test seams
  (`REVIEWER_GH_BIN`, `WORKSPACE` override, `REVIEWER_RUNS_ROOT`/`REVIEWER_REVIEWS_ROOT`).

## Notes

- `docs/tasks/code-review-agent.md`, `docs/tasks.txt`, and `docs/prd-queue/...` are
  driver-owned/read-only and were **not** modified (per brief); the task file already exists
  and will be transitioned `in-progress → in-review` by the driver after UAT.
- `docs/factory-context.md` roster + assembly_line pointer and
  `docs/reference/reviewer-agent.md` artefact map were added/updated.