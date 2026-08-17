## Decision: Code reaches master only via PR merge — tracking/evidence syncs direct

**Status**: accepted
**Date**: 2026-08-18 02:27
**Task**: implementer-delivery-failure-loud
**Project**: software-factory
**Session**: sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/session.jsonl

### Context

The headless factory loop runs in CI (runner host-side; the agent container never touches git). After the first cloud task completed (PR #10 merged, task `complete`), a full history audit of `origin/master` (388 commits) classified every non-merge commit touching code paths (`bin/`, `config/`, `.github/`, `opensource/`) and found the loop had pushed code directly to master.

### Problem

Where does code physically land, and can it bypass the human review gate? The audit found:

- **9 loop-authored direct-code commits** total: 1 during the cloud era — `bdac29e` (run 32056463396, impl session 8370f85b, 08-17 19:08) swept `bin/implementer-run.sh` + `bin/test-implementer-driver.sh` to master — **exactly the files PR #10 later merged** (code hit master twice: direct, then via merge). The other 8 (`0cfa941`, `9745c04`, `6cf4613`, `223b2bd`, `a2c1b89`, `1cfc369`, `321c127`, `68c8937`) were pre-cloud local-run era (08-14 → 08-17 03:46).
- The sweep's content was the **pre-review** implementation (the reviewer REQUEST_CHANGES'd PR #10 for delivery-integrity defects) — master held un-reviewed code for ~1h until the merge re-applied it.
- Mechanics: archive/tracking commits are **authored by the driver scripts** (`bin/implementer-run.sh`, `bin/review-run.sh`) in the runner's workspace checkout; the **push to master is executed by the CI workflow's "Sync tracking commits to master" step** (`git push origin master`, `if: always()`). The one code sweep came from the run-3-era driver's old delivery path (`run <uuid> [factory]` commit pattern), removed when `push_and_pr` (branch + PR) took over by run 4.
- Latent risk: the sync step uses `git add -A` — safe only because code changes live in the separate worktree clone, never in the runner checkout.

### Alternatives

- **Keep the old direct-delivery path** (commit worktree → master): rejected — it bypasses the review gate entirely, which is the entire point of the PR flow (decisions 05/06).
- **Route tracking/evidence through PRs too**: rejected — evidence (sessions, decisions, task transitions) is not mergeable code; gating it adds review noise and slows the loop. The two-stream model (decision 07) stays.
- **Block all direct pushes at the remote (ruleset)**: deferred — branch protection/rulesets can't distinguish "tracking docs" from "code" cleanly; hardening the sync step + a CI tripwire is cheaper.

### Decision

Code — any change under `bin/`, `config/`, `.github/`, `opensource/`, `src/` — reaches `master` **only via a PR merged by the user** (merge authority, decision 05). Tracking/evidence (docs-only: sessions, reports, decisions, task-file transitions) is authored by the drivers and pushed to master by the CI sync step on every run. The legacy "commit worktree → master" delivery path is dead; `push_and_pr` pushes only the PR branch.

### Rationale

The PR is the only reviewed, user-gated artifact; evidence must not be gated or it stops flowing (ephemeral runners lose everything uncommitted). The incident was a legacy-path regression, not a design flaw — one run's driver still had the old delivery step. Keeping the invariant explicit + hardening the sync step prevents recurrence at the point where code could re-enter master silently.

### Consequences

- **Per-task reports are "latest wins"**: `docs/implementations/<slug>/report.md` and `docs/code-reviews/<slug>/report.md` are overwritten by each run's archive commit — only the last impl + last review report survive per task. Durable per-run evidence = `docs/knowledge/sessions/<uuid>/session.jsonl` (accumulates) + raw bundles in `factory-traces/runs/<run-id>/` (private).
- **Sync step hardening pending**: narrow `git add -A` → `git add docs/` so a code file can never be swept into a sync push; add a CI tripwire that fails non-merge code-path commits.
- **Master carries un-reviewed evidence by design** — `master` is not "everything reviewed"; it's "code reviewed + evidence synced". A rejected PR leaves its run's evidence on master (no cleanup path yet).
- Auditing direct-code pushes is now scriptable (non-merge commits touching code paths).

### Revision triggers

- Any future run whose archive commit touches code paths (the sweep regresses) — re-run the classification audit.
- If the sync step's `git add -A` is not narrowed to `docs/` and a code file is swept in.
- If evidence gating is introduced (tracking via PRs), the two-stream model changes.
