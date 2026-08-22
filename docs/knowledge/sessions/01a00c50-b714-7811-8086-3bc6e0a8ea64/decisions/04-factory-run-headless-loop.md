## Decision: Extend factory-run.sh with --headless loop to APPROVE

**Status**: accepted
**Date**: 2026-08-17 03:26
**Task**: [headless-agent-containerisation](../../../../tasks/headless-agent-containerisation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Extend bin/factory-run.sh with --headless

### Context

`bin/factory-run.sh` chains implement → review but is single-shot: an
interactive UAT gate sits between the stages, and on `REQUEST_CHANGES` a human
must later re-run `review-run.sh` and manually kick `implementer-run.sh
--revise`. The backend host must run unattended and drive the revision loop to
review success.

### Problem

The same chain script must serve both interactive use (UAT gate preserved) and
headless CI use (no prompts, automatic revision loop), without duplicating the
chain logic.

### Alternatives

- **New `bin/factory-host.sh`** — rejected: duplicates the chain logic,
  bigger diff, two scripts to keep in sync.
- **Orchestrate the loop in the CI workflow YAML** — rejected: pushes loop
  control into CI syntax, harder to test and to reuse locally in herdr.

### Decision

Extend `bin/factory-run.sh` with `--headless`:

- Skip the interactive UAT gate (equivalent to today's `--yes`, but explicit).
- After the review stage, read the verdict from the archived review report
  (`docs/code-reviews/*-<slug>/report.md`, first line `APPROVE` /
  `REQUEST_CHANGES` — the same source `implementer-run.sh --revise` uses).
- On `REQUEST_CHANGES` and iterations below the cap (default 3, configurable):
  run `implementer-run.sh --revise <pr>` then `review-run.sh <pr>` again.
- Stop at `APPROVE` (task `in-review`, merge-ready PR — decision 02) or on cap
  exhaustion (exit non-zero, last review report surfaced for the user).
- Keep `--task <slug>` / `--pick` and `--dry-run` pass-through.

### Rationale

Smallest diff; interactive semantics untouched (the UAT gate is skipped only
under `--headless`); the loop is deterministic bash, testable through the
existing `FA_RUN_IMPLEMENTER` / `FA_RUN_REVIEWER` stub seams in
`bin/test-factory-run.sh`; revisions reuse the existing `--revise` mode and its
binding-authority semantics.

### Consequences

- `factory-run.sh` gains loop state (revision count, verdict read-back).
- CI runs it with `--headless`; herdr (local dev) can run the same invocation.
- The merge boundary is unchanged: the loop never merges; the user merges after
  UAT (`merge-pr.sh`).

### Revision triggers

- The cap proves too tight for real revision workloads (per-task budgets).
- Parallel task execution is wanted (the loop is single-task today).
- The verdict read-back (report first line) becomes unreliable.
