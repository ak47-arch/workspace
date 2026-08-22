## Decision: CI runs must sync tracking commits to master — ephemeral runners discard local commits

**Status**: accepted
**Date**: 2026-08-17 17:27
**Task**: [headless-agent-containerisation](../../../../tasks/headless-agent-containerisation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: factory.yml gains a final "Sync tracking commits to master" step (if: always()): git add -A, commit if dirty, git pull --rebase origin master (tolerating a concurrent mer

### Context

The drivers persist workspace-root tracking state on the checkout: archives in
`docs/implementations` + `docs/code-reviews`, knowledge sessions, task
transitions (`in-prd → in-progress → in-review`), PR-tracking rows, and
`docs/tasks.txt` moves. Locally these accumulate on the operator's master and
ride up with the merge push (decision 07 of the harness: the chain never pushes
master). On a GitHub-hosted runner the checkout is **ephemeral** — anything not
pushed is destroyed with the VM.

### Problem

Without a sync step, a cloud run would raise the PR and post the review, but the
task file would remain `prd-ready` locally, archives and sessions would be lost,
and end-to-end traceability would break — while the run reports success.

### Alternatives

- **Let tracking ride the PR branch** — rejected: the PR already exists; new
  branch commits would grow the diff with metadata.
- **Sync only on success** — rejected: failure-path reverts (task → `prd-ready`,
  partial reports) must persist too.

### Decision

`factory.yml` gains a final **"Sync tracking commits to master"** step
(`if: always()`): `git add -A`, commit if dirty, `git pull --rebase origin
master` (tolerating a concurrent merge), then `git push origin master`. It
pushes metadata only — never code, never a merge — and runs even when the loop
fails so reverts/partial reports persist.

Also discovered and fixed: the repo_map checkout step must map local directory
names to GitHub repo names for the two mismatches —
`llm → llamacpp_inference_server`, `survival-infrastructure → goal-agent` — and
must not reference unset shell vars (`$WORKSPACE` is undefined on the runner;
`set -u` aborts).

### Rationale

Traceability is a core factory value (end-to-end traceability task); losing
transitions/archives on ephemeral runners silently breaks it. Metadata-only
pushes to master keep the authority split (code still only reaches master via
human-reviewed merges) while preserving state.

### Consequences

- Every CI run ends by pushing its tracking commits to master (same content
  that locally rides up at merge time).
- A concurrent PR merge mid-run is tolerated via `pull --rebase`.
- `$WORKSPACE`-dependent driver messages must be reviewed for runner contexts
  (the runner sets `$GITHUB_WORKSPACE`, not `$WORKSPACE`).

### Revision triggers

- The factory adopts self-hosted runners with persistent checkouts (sync step
  becomes optional).
- Tracking commits start conflicting regularly with merges.
