# Code Review
- Reviewed: ak47-arch/workspace#1 (repo: ak47-arch/workspace, PR #1)
- Task: code-review-agent · PRD: /workspace/docs/prd-queue/2026-08-13-code-review-agent.md · Review session: 19cb853b-a2e9-4eb6-865a-138864ba1934
- Base: d72dcf71d08cfc1bff6a1dbfce38474fa643a56d → Head: 0cfa9419bebca05200733258f30855b5ea2b3528

## Verdict
APPROVE — the PR faithfully implements the PRD (driver + persona + review-ops skill + ponytail pass), all PRD verification commands pass or are correctly deferred, no blocking findings; only minor advisory over-engineering items.

## Verification results
- `bash bin/test-review-driver.sh` — **RAN**, exit 0, **50 passed / 0 failed**. Covers arg parsing (URL/owner-repo#num/bare-slug/bare-num/--pick), slug resolution (title + branch), repo_map + PRD detection, run-dir/brief contract, PR-head checkout + base fetch + clean worktree, env allowlist (no GITHUB_TOKEN, forces PONYTAIL_DEFAULT_MODE=ultra), six ponytail `--skill` flags, archive to `docs/code-reviews/<date>-<slug>/`, dry-run transitions, mock-gh call-counted comment/label, static no-token guardrail.
- `bash bin/test-transition-task.sh` — **RAN**, exit 0, **45 passed / 0 failed** (regression).
- `bash bin/test-implementer-driver.sh` — **RAN**, exit 1, **28 passed / 1 failed**: `resolve_repo MANIFEST_BRANCH = 'master' — expected public-release`. Verified as **environmental, not a regression**: `workspace-portability/workspace_restore_manifest.json` is gitignored (`/workspace-portability/` in `.gitignore`, confirmed `git check-ignore`), so the sandbox fixture clone lacks it and the lookup falls back to `master`. `bin/implementer-run.sh` diff touches ONLY the label block (`gh label create` + `--label factory:needs-review`) — `resolve_repo`/manifest lookup unchanged. Deferred to host (file exists host-side).
- `bash -n` on `bin/review-run.sh`, `bin/test-review-driver.sh`, `bin/implementer-run.sh` — **RAN**, pass.
- `shellcheck` — **deferred** (not installed in this container; `bash -n` + unit suite cover logic). Matches implementer's report.
- Real container `podman` run / real `gh` resolve/comment/label / `--pick` against a live GitHub PR — **deferred** (no podman, no gh, no GitHub credential in this container; host owns these). Non-deterministic APPROVE/REQUEST_CHANGES fixture sanity and container guardrails (no commit/gh/token) are host-side UAT items.

## Story-by-story
- [PASS] US1 — Trigger `bin/review-run.sh <pr>` → structured report. `bin/review-run.sh` (761 lines) mirrors the implementer driver: resolve → run-dir → worktree → podman → archive → comment → label → transition. Arg-parsing tests pass.
- [PASS] US2 — Driver resolves repo/slug/PRD from PR metadata. `resolve_pr` → `pr_metadata` (gh `pr view`) → `resolve_slug` (title `[factory] <slug>:` / branch `factory/<slug>/<ts>`) → `resolve_repo` (task `Project` → `config/reviewer.json` repo_map + PRD from `docs/prd-queue/*-<slug>.md`). Tests pass for title/branch/repo_map/PRD location.
- [PASS] US3 — Worker checks out PR head read-only, diffs `base...head`, runs PRD verification. `prepare_run_dir` fetches head SHA + base ref, checks out head, points origin at real remote; worktree-checkout, base...head-diff-resolves, and worktree-clean tests pass. `review-ops` §2/§3 instruct the read-only diff + running the PRD verification commands.
- [PASS] US4 — Deterministic + judgment checks. `.agents/skills/review-ops/SKILL.md` declares D1–D7 + J1–J5 (incl. ponytail pass); `.pi/agents/code-reviewer.md` persona. No config registry (YAGNI per PRD).
- [PASS] US5 — Structured report posted to PR + archived. Fixed schema in review-ops; `archive()` → `docs/code-reviews/<date>-<slug>/` (report+decisions+brief); `post_pr_comment()` via gh. Archive + mock-gh `<comment>` tests pass.
- [PASS] US6 — REQUEST_CHANGES does not merge/complete. Success path transitions only to `in-review`; `fail_run` leaves task `in-progress`; no merge path exists.
- [PASS] US7 — On success transitions `in-progress → in-review` + session link. `transition()` → `transition-task.sh <slug> --to in-review --session <uuid>:review`; dry-run test passes.
- [PASS] US8 — Reuses `sandbox:latest`, config shape mirrored. `config/reviewer.json` mirrors `implementer.json` (`repo_map`, `model`, `timeout_sec`, `respawn_cap`, `env_allowlist`, `image`, `runs_root`) + `reviews_root` + `ponytail{skills_dir, default_mode}`. Image `sandbox:latest`, unchanged.
- [PASS] US9 — Checks declared in versioned skill/persona. New `.agents/skills/review-ops/SKILL.md` + `.pi/agents/code-reviewer.md`; robustness = skill edit.
- [PASS] US10 — Reviewer read-only, no commits, no GH credential. Persona + review-ops + brief forbid mutation/gh; `write_env_file` whitelists only LLM/Langfuse vars + `PONYTAIL_DEFAULT_MODE`; env-file excludes `GITHUB_TOKEN`; driver never references `GITHUB_TOKEN` (tests pass). `gh_call` lazy seam keeps all gh host-side.
- [PASS] US11 — Ponytail over-engineering pass (six skills at ultra, advisory). Driver passes six `--skill /workspace/opensource/ponytail/skills/{...}` flags + forces `PONYTAIL_DEFAULT_MODE=ultra`; review-ops J4 runs `ponytail-review` on `base...head` as advisory; debt harvest into UAT. Six-flag count + per-skill + opensource-presence + ultra-env tests pass.

## Deterministic checks
- [PASS] D1 — PR metadata sane. Head = 0cfa941 (implementer commit `implementer(code-review-agent): run d7a5fbb9… [factory]`); base = d72dcf7; both rev-parse; diff is non-empty (10 files, +1541/-8). Slug `code-review-agent` resolves from branch/title pattern; repo `ak47-arch/workspace`.
- [PASS] D2 — Worktree clean / read-only. `git status --porcelain` empty; HEAD detached at PR head; reviewer made no mutations (guardrail held).
- [PASS] D3 — Scope containment. All 10 changed files are within the PRD file-tree diff + data-model changes (driver, test, config, persona, skill, reference, factory-context, implementer-run label, task file, tasks.txt). No stray deps, no unrelated refactor (implementer-run.sh change is only the label block).
- [PASS] D4 — Scope ⊆ PRD file-map. Every PRD-claimed NEW file present in diff: review-run.sh, test-review-driver.sh, reviewer.json, code-reviewer.md, review-ops/SKILL.md, reviewer-agent.md, factory-context.md (edit), implementer-run.sh (edit), task file (edit — session entry). PRD itself (docs/prd-queue/2026-08-13-code-review-agent.md) and docs/reviews/ are in base/unmoved as expected.
- [PASS] D5 — Story → diff coverage. All 11 stories map to concrete diff files/hunks (see story-by-story). No capability without a story.
- [PASS] D6 — No secrets / stray deps. `git grep` over base...head for `ghp_`, `AKIA`, `sk-…`, `PRIVATE KEY` → none. No new gem/requirements/package added.
- [PASS] D7 — Implementer report matches actual diff. Report (`docs/implementations/2026-08-14-code-review-agent/report.md`) claims 50/50, 45/45, 28/1-env — all reproduced exactly. Claims story/file coverage consistent with the diff; verification claims plausible.

## Judgment checks
- [PASS] J1 — Story intent. All stories would produce the observable behavior described: a driver resolves a PR and produces an archived+posted structured report; worker runs PRD verification + deterministic/judgment checks; ponytail pass advisory; lifecycle stays UAT-gated.
- [PASS] J2 — PRD-decision conformance. Archive to `docs/code-reviews/` (distinct from `docs/reviews/`); checks in versioned skill/persona (no config registry); read-only worker; no GH credential in container; six `--skill` flags + ultra; implementer tags `factory:needs-review` after idempotent `gh label create --force`. All honored.
- [PASS] J3 — Edge / error paths. Missing gh → `die` with clear message; missing task file / PRD → `die`; respawn loop capped; liveness/timeout kill; partial-review archive (report.md stub + `--keep-logs`); `fail_run` leaves task in-progress; empty/bad PR args handled; `qualify_repo`/`default_repo` have env overrides + fallbacks. Robust.
- [PASS] J4 — Ponytail over-engineering pass (advisory subclass). See findings below — minor advisory only; none flip the verdict.
- [PASS] J5 — UAT gaps. Real container run, real gh, `--pick` on live GitHub, APPROVE/REQUEST_CHANGES fixture sanity on a real container, and `factory:needs-review` tagging on a real implementer PR must be exercised host-side.

## Findings
### Blocking (→ REQUEST_CHANGES)
- None.

### Advisory (consider / over-engineering)
- `bin/review-run.sh:L322` shrink: `WORKTREE="$RUN_DIR/worktree"` assigned twice in `prepare_run_dir` (same value). Drop line 322.
- `bin/review-run.sh:L234-287` shrink: `pr_metadata()` spawns 5 separate `python3` subprocesses to parse the same `gh pr view` JSON (one field each). Parse once (single python3/jq emitting all fields) — ~15 lines shorter.
- `bin/review-run.sh:L47-95` yagni: full bash/jq-config fallback block duplicates the JSON config values in a here-doc. jq is present in the sandbox image; the fallback doubles maintenance surface. Keep only if parity with `implementer-run.sh` (which has the same pattern) is a hard requirement.
- `config/reviewer.json` / `bin/review-run.sh` yagni: `reviews_root`/`keep_worktree`/`liveness_*`/`cleanup_enabled` knobs mirror the implementer config and are exercised in tests — reasonable parity, low priority.

## Ponytail debt (harvested from changed files)
- No `ponytail:` shortcut markers in the changed files (the two `grep` matches in `.agents/skills/review-ops/SKILL.md` are just the format documentation, not debt markers). → No ponytail debt.

## UAT hand-off list
1. **Real container run**: `bin/review-run.sh <factory-PR> --dry-run` on the host; confirm run dir, PR-head checkout, brief, and podman invocation (six `--skill` flags, `PONYTAIL_DEFAULT_MODE=ultra`, no GH token). Then a real (non-dry) run to verify the report posts to the PR and the label is applied.
2. **Non-deterministic sanity**: run an APPROVE-shaped fixture and a REQUEST_CHANGES-shaped fixture (blocking finding) on a real container and confirm the verdict flips; confirm advisory-only findings never flip to REQUEST_CHANGES.
3. **Container guardrails**: confirm the worker made no commits, no `gh` call from the container, and no token env is set in the container.
4. **Real gh / --pick**: confirm `gh` is authenticated host-side and `--pick` selects the oldest open `factory:needs-review` PR.
5. **Implementer label**: confirm a freshly raised implementer PR arrives tagged `factory:needs-review` (the `--label` addition).
6. **Manifest regression**: re-run `bin/test-implementer-driver.sh` on the host (where `workspace-portability/workspace_restore_manifest.json` exists) to confirm the 1 failure disappears.
7. **Approve the `bin/implementer-run.sh` label block** (`--label factory:needs-review` + idempotent `gh label create --force`) as inert metadata for the review seam.
