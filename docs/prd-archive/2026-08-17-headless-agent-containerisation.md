# PRD: Headless Agent Containerisation — backend implement → review loop delivering merge-ready PRs

**Date**: 2026-08-17 03:26
**Status**: Final
**Owner**: software-factory workspace
**Task**: headless-agent-containerisation
**Session**: `docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/01-headless-backend-host-scope.md`
  - `docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/02-merge-ready-deliverable.md`
  - `docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/03-github-actions-fast-path.md`
  - `docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/04-factory-run-headless-loop.md`

## Problem statement

The factory's implement → review pipeline is manual and session-bound. The user
must invoke `bin/factory-run.sh` (or the drivers) from their interactive
session, answer a UAT gate between the stages, and on `REQUEST_CHANGES`
manually re-run the review and `implementer-run.sh --revise`. The host role is
played inside the user's TUI session, which blocks for the entire run.

Goal (decision 01): once a PRD is **Final** (task `prd-ready`), the user stops
being involved. Everything — implementation, review, revision iterations —
runs headless in the backend, and the user receives a **merge-ready PR**
(decision 02): reviewed, approved, merge remains the user's UAT action.

## Solution overview

Extend the existing chain script with a headless loop, and run it from GitHub
Actions (decision 03):

1. `bin/factory-run.sh` gains `--headless` (decision 04): no UAT gate; after
   review, on `REQUEST_CHANGES` run `implementer-run.sh --revise <pr>` →
   re-review, up to a cap (default 3); stop at `APPROVE`; on cap exhaustion
   exit non-zero with the last review report surfaced.
2. A workflow `.github/workflows/factory.yml` on the workspace repo triggers on
   push to `docs/prd-queue/**.md`, verifies the PRD is `Final` + task
   `prd-ready`, and runs the loop on `ubuntu-latest` with docker as the
   container runtime (`IMPLEMENTER_PODMAN_BIN=docker` seam; docker ships on
   hosted runners) and the sandbox image built in-job.

The workers stay containerised in the existing `sandbox:latest` sandbox — the
"agent containerisation" line of the bundle is satisfied by the portable
(env-driven, seam-based) host loop driving containerised workers. herdr remains
the local runtime for the same loop (dev visibility); Woodpecker remains the
self-hosted upgrade path — neither is built now (decision 03).

## User stories

1. As the user, when a PRD in `docs/prd-queue/` is pushed with `**Status**:
   Final` and its task file is `prd-ready`, a CI run starts automatically —
   no manual invocation.
2. As the user, the run needs no interactive input: no UAT prompt, no
   keystrokes, end to end.
3. As the user, when the review returns `REQUEST_CHANGES`, the pipeline
   automatically runs a revision (`implementer-run.sh --revise <pr>`) and
   re-reviews, repeating up to the configured cap, without my involvement.
4. As the user, when the review returns `APPROVE`, the pipeline stops and
   leaves: the branch pushed, the PR raised and labelled, the review report
   posted to the PR, and the task in `in-review` — a merge-ready PR.
5. As the user, when the revision cap is exhausted without `APPROVE`, the run
   fails with the latest review report available, so I can decide.
6. As the user, the merge is not part of the pipeline — I run `bin/merge-pr.sh`
   after my own UAT (decision 02).

## Implementation decisions

- **Backend runtime**: GitHub Actions hosted runner (`ubuntu-latest`); herdr
  and Woodpecker deferred as extension paths (decision 03).
- **Loop shape**: `--headless` mode on `bin/factory-run.sh` (decision 04) —
  skip the UAT gate, verdict read-back from `docs/code-reviews/*-<slug>/report.md`
  (first line), revise loop with cap default 3, stop at `APPROVE`.
- **Trigger**: workflow `on: push` with `paths: ['docs/prd-queue/**.md']`; a
  status gate step checks the PRD header (`**Status**: Final`) **and** the task
  file (`**Status**: prd-ready`) — if either is missing, exit 0 silently (an
  early push to the queue must not half-run); the changed slug is passed as
  `--task` (fallback `--pick` when ambiguous).
- **Container runtime**: docker on the runner via the existing
  `IMPLEMENTER_PODMAN_BIN` seam (the driver's podman flags are docker-
  compatible: `run --rm --network=host --env-file -v --name`, `rm -f`,
  `stop -t`, `ps --format`). Sandbox image built in-job from
  `workspace-portability/container/Dockerfile` (ghcr publishing deferred).
- **Checkout**: workspace repo + every repo_map target (from
  `config/implementer.json`), shallow, so the driver's
  `$WORKSPACE/$TARGET_REPO` resolution finds git repos.
- **Secrets (GitHub → env)**: `FACTORY_GH_PAT` (cross-repo push/PR + PR
  posting — `GITHUB_TOKEN` is single-repo), `OPENROUTER_API_KEY`,
  `ANTHROPIC_API_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`,
  `LANGFUSE_BASE_URL`; `gh auth login --with-token` + `gh auth setup-git` so
  `git push` works in the job.
- **Task lifecycle**: unchanged — implementer run transitions
  `in-prd → in-progress`; review transitions `in-progress → in-review` on any
  verdict; revisions never transition (stay `in-review`); the loop ends the
  task at `in-review`. PRD stays in `docs/prd-queue/` until the user merges
  and the task completes.
- **Concurrency**: one task at a time per run (parallel worktrees deferred).

## Testing decisions

- **Seam**: the existing `bin/test-factory-run.sh` stub seams
  (`FA_RUN_IMPLEMENTER`, `FA_RUN_REVIEWER`, `FACTORY_WORKSPACE`) let the
  headless loop be tested with fake drivers (scripted verdicts:
  APPROVE-first, REQUEST_CHANGES→revise→APPROVE, cap exhaustion) without any
  real git/gh/container.
- **Unit**: `--headless` flag parsing, gate-skip, verdict read-back, revise
  invocation count, cap behaviour, exit codes.
- **Integration**: `bin/factory-run.sh --headless --dry-run` against a fixture
  workspace proves the loop wiring; the drivers' own `--dry-run` semantics are
  preserved.
- **Real CI**: a manual `workflow_dispatch` run with a real Final PRD proves
  the end-to-end flow (PR raised, review posted, task `in-review`).

## Architecture

### Data flow

```
push to workspace repo (docs/prd-queue/*.md + docs/tasks/*.md)
  → GitHub webhook → workflow factory.yml (paths filter)
  → job (ubuntu-latest):
      checkout workspace + repo_map targets
      build sandbox:latest (Dockerfile)
      export secrets → env (PAT, LLM creds); gh auth
      status gate: PRD Final + task prd-ready (else exit 0)
      bin/factory-run.sh --headless [--task <slug>]
        → implementer-run.sh --pick/--task        (in-prd → in-progress)
              run dir ~/.factory/runs/<slug>-<ts>/ · sandbox container ·
              worktree clone · host commit/push · gh pr create
              (label factory:needs-review)
        → review-run.sh <pr>                      (in-progress → in-review)
              sandbox · report → docs/code-reviews/ · PR comment ·
              label factory:reviewed-ok|review-blocked
        → verdict read-back (report first line)
              REQUEST_CHANGES & n < cap → implementer-run.sh --revise <pr>
                  (no transition; same branch; binding review)
                  → review-run.sh <pr> → loop
              APPROVE → stop (task in-review, merge-ready PR)
              cap exhausted → exit non-zero (last report surfaced)
```

### Contracts

- `bin/factory-run.sh --headless [--task <slug>|--pick] [--dry-run]` —
  new flag; `--yes`/interactive semantics unchanged.
- Revision cap: env `REVISION_CAP` (default 3) — configurable, no new config
  file.
- **Verdict contract**: `docs/code-reviews/<date>-<slug>/report.md` carries the verdict on the line starting `APPROVE` / `REQUEST_CHANGES` under its `## Verdict` section (review-ops schema, §6). Read-back uses the same parse the review driver already uses — `grep -m1 '^APPROVE\|^REQUEST_CHANGES'` (see `bin/review-run.sh` ~line 791) — applied to **the report just archived by the completed review run** for the slug (same-day archives overwrite the date-scoped dir). Do NOT assume line 1: real reports open with `# Code Review`. Empty verdict (e.g. a `# Partial review` failure report) ⇒ surface the report, treat as non-`APPROVE`, exit non-zero, do NOT revise.
- Workflow: `.github/workflows/factory.yml` — paths filter, status gate,
  provisioning steps, `factory-run.sh --headless` step.
- Required repo secrets: `FACTORY_GH_PAT`, `OPENROUTER_API_KEY`,
  `ANTHROPIC_API_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`,
  `LANGFUSE_BASE_URL`.

### Data model changes

None. No database, no schema, no new lifecycle states. Existing task lifecycle
(`in-prd → prd-ready → in-progress → in-review → complete`), PR tracking rows,
and archives are reused unchanged.

## Location (file map)

| Change | Path |
|---|---|
| `--headless` mode + revise loop + verdict read-back | `bin/factory-run.sh` |
| CI trigger + provisioning + loop invocation | `.github/workflows/factory.yml` (new) |
| Loop tests (stub seams, scripted verdicts) | `bin/test-factory-run.sh` |
| Task lifecycle tracking | `docs/tasks/headless-agent-containerisation.md` |
| Knowledge decisions 01–04 | `docs/knowledge/sessions/01a00c50-…/decisions/` |

Untouched: `bin/implementer-run.sh`, `bin/review-run.sh`, `bin/transition-task.sh`,
`bin/sandbox-build.sh`, `config/implementer.json`, `config/reviewer.json`.

## Acceptance (verification)

```bash
# 1. Headless loop unit tests (scripted verdicts, no real drivers/containers)
bash bin/test-factory-run.sh

# 2. Dry-run wiring against a fixture workspace
FACTORY_WORKSPACE=<fixture> bin/factory-run.sh --headless --dry-run

# 3. Real end-to-end (manual, workflow_dispatch): a real Final PRD →
#    PR raised + review posted + task in-review + merge-ready PR.
#    Precondition: repo secrets pre-configured (FACTORY_GH_PAT, LLM keys,
#    Langfuse vars) before the first dispatch.
```

"Done" = a Final PRD pushed to the workspace repo produces a reviewed
(`APPROVE`), merge-ready PR with the task at `in-review`, with no user
interaction between push and result.

## Out-of-scope

- Containerising the host driver itself into an image (portable driver image —
  later; the sandbox image already exists).
- herdr integration (local runtime / persistent agent host) and Woodpecker
  migration — documented extension paths, not built (decision 03).
- Parallel task execution (multiple worktrees at once).
- Per-task revision budgets / cap tuning UI.
- The thermisticles / cloud machine move (workspace-portability tasks).

## Further notes

- Merge boundary: the pipeline never merges and never pushes master (existing
  decisions 05/07; decision 02). The PRD moves to `docs/prd-archive/` only
  when the user merges and the task completes.
- The same `--headless` invocation runs locally under herdr for dev visibility
  without code changes — the loop is runtime-agnostic by construction.
