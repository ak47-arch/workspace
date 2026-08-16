# Implementer Report — headless-agent-containerisation

- **Task slug**: headless-agent-containerisation
- **Impl session UUID**: 771b4017-a17d-4464-9896-476407652701
- **PRD**: `docs/prd-queue/2026-08-17-headless-agent-containerisation.md`
- **Status**: All stories DONE (verification #1 & #2 green; #3 is UAT-only, cannot run in sandbox)
- **Exit code**: 0

## Summary of changes

| File | Change |
|---|---|
| `bin/factory-run.sh` | Added `--headless` mode (decision 04): skips the UAT gate, runs an autonomous implement→review loop that reads the verdict back from the archived review report, and on `REQUEST_CHANGES` invokes `implementer-run.sh --revise <pr>` then re-reviews, up to `REVISION_CAP` (default 3), stopping at `APPROVE`; cap exhaustion / empty-verdict / missing-report all exit non-zero with the last report surfaced. Verdict read-back mirrors the review driver's parse (`grep -m1 '^APPROVE\|^REQUEST_CHANGES'`) applied to `docs/code-reviews/<date>-<slug>/report.md`. No merge path added. |
| `bin/test-factory-run.sh` | Added headless loop tests via existing stub seams (`FA_RUN_IMPLEMENTER`/`FA_RUN_REVIEWER`/`FACTORY_WORKSPACE`) plus a verdict-writing stub reviewer driven by a scripted verdicts file (`FA_VERDICTS`). |
| `.github/workflows/factory.yml` (new) | `on: push` filtered to `docs/prd-queue/**.md` (+ `workflow_dispatch`), status gate (PRD `Final` + task `prd-ready`, else silent exit 0), slug resolution with `--pick` fallback, repo_map target checkouts, in-job sandbox build, `gh auth login --with-token` + `setup-git`, secrets → env, and the `factory-run.sh --headless` invocation with `IMPLEMENTER_PODMAN_BIN=docker`. |
| `.gitignore` | Un-ignored `/.github/` so the root-level factory workflow is trackable/committable (it was blanket-ignored, which would have silently dropped the workflow). |

Untouched (as the PRD requires): `bin/implementer-run.sh`, `bin/review-run.sh`,
`bin/transition-task.sh`, `bin/sandbox-build.sh`, `config/implementer.json`,
`config/reviewer.json`.

## Per-story status & evidence

| Story | Status | Evidence |
|---|---|---|
| 1. CI auto-starts on Final+prd-ready PRD push | DONE | `.github/workflows/factory.yml` `on.push.paths: docs/prd-queue/**.md`; status-gate step verified locally against Final/Draft fixtures → only Final+prd-ready slugs pass, others exit 0 silently. |
| 2. No interactive input end to end | DONE | `--headless` skips the UAT gate (no `read`). Test `headless skips UAT gate (no stdin interaction)` passes; `headless dry-run exits 0`. |
| 3. REQUEST_CHANGES → auto-revise → re-review up to cap | DONE | `headless_loop` invokes `"$IMPLEMENTER" --revise "$PR_ARG"` on REQUEST_CHANGES while `n < REVISION_CAP`. Test `REQUEST_CHANGES → revise → APPROVE`: exactly 1 revise + 2 reviews. |
| 4. APPROVE → stop with merge-ready PR, task in-review | DONE | `headless_loop` exits 0 on `APPROVE*`. Tests `headless APPROVE exits 0`, `reviewer ran once`, `no revise on APPROVE`. Reviewer driver already posts report + labels + transitions to `in-review` (authority split preserved). |
| 5. Cap exhaustion → fail with last report surfaced | DONE | `headless_loop` exits 1 on cap exhaustion after `surface_report`. Test `REVISION_CAP=2` → exactly 2 revises, exit 1, `cap exhausted` reported. `REVISION_CAP=0` → no revise, exit 1. |
| 6. Merge not part of pipeline | DONE | No merge path added to `factory-run.sh`; authority-split tests `no merge call reaches any driver` still pass. |

## Verification results

```bash
# Acceptance #1 — headless loop unit tests (scripted verdicts, stub drivers)
bash bin/test-factory-run.sh
# → 40 passed, 0 failed  (22 pre-existing + 18 new headless assertions)

# Acceptance #2 — dry-run wiring against a fixture workspace
FACTORY_WORKSPACE=<fixture> FA_RUN_IMPLEMENTER=<stub> FA_RUN_REVIEWER=<stub> \
  bin/factory-run.sh --headless --dry-run
# → implementer --pick --dry-run runs; review skipped; exit 0

# Acceptance #3 — real end-to-end (manual workflow_dispatch)
# NOT RUNNABLE in this sandbox: requires GitHub repo + pre-configured secrets
# (FACTORY_GH_PAT, LLM keys, Langfuse vars) and a real container build.
# → UAT hand-off (see below).
```

Additional in-sandbox checks:
- `bash -n bin/factory-run.sh` and `bash -n bin/test-factory-run.sh` → syntax OK.
- `git check-ignore .github/workflows/factory.yml` → trackable (workflow will be committed by the host).
- Workflow status-gate shell logic validated locally for: single ready → `--task <slug>`; ambiguous (2 ready) → `--pick`; Draft/not-ready → silent exit 0; manual-dispatch ready slug → pass; manual-dispatch unknown slug → silent exit 0.
- Docker/PAT-less: sandbox image build and real driver runs require docker + secrets, not available here.

## UAT hand-off list

1. **Acceptance #3 (real CI end-to-end)**: On the workspace repo, pre-configure repo secrets (`FACTORY_GH_PAT`, `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_BASE_URL`), then run a manual `workflow_dispatch` with the real `headless-agent-containerisation` PRD/task (or another Final+prd-ready PRD). Confirm: PR raised + `factory:needs-review` label, review report posted, `factory:reviewed-ok|review-blocked` label, task at `in-review`, and a merge-ready PR.
2. **YAML validation**: `factory.yml` could not be linted offline (no actionlint/yamllint/PyYAML in the sandbox). Recommend `actionlint .github/workflows/factory.yml` before/at merge, or rely on GitHub's parser on first push.
3. **repo_map target checkouts**: the workflow attempts a shallow clone of every non-`.` repo_map target under `github.repository_owner`. If any target lives under a different owner/org or is unreachable, it logs a WARN and continues (non-fatal). Confirm the owner assumption matches the real repo(s).
4. **`.gitignore` scope**: `!.github/` un-ignores the whole root `.github/` dir (git's ignore negation cannot re-include a file inside an excluded parent more narrowly). The workspace root currently holds no other workflows; confirm this is acceptable. See Decision 05.

## Emerged decisions

- `05-headless-ci-gitignore-track-workflow.md` — the `.github/` blanket ignore had to be negated so the root factory workflow is committable.

## Exit

Exit 0 — all implementable stories complete and verified to the extent possible in the sandbox; real-CI is a documented UAT hand-off.
