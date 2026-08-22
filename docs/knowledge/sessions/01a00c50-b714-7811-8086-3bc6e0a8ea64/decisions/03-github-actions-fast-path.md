## Decision: GitHub Actions as the fast-path backend runtime (YAGNI)

**Status**: accepted
**Date**: 2026-08-17 03:26
**Task**: [headless-agent-containerisation](../../../../tasks/headless-agent-containerisation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: GitHub Actions hosted runners (ubuntu-latest) now.

### Context

The bundle's goal is a headless backend host: once a PRD is Final, everything
runs unattended and the user receives a merge-ready, review-approved PR. Three
candidate runtimes emerged: herdr (background agent-terminal server, already
vendored + installed), GitHub Actions (hosted CI), and Woodpecker (self-hosted
CI, vendored). The drivers (`implementer-run.sh`, `review-run.sh`,
`factory-run.sh`) already exist, are tested, and are CI-shaped (deterministic
bash, container workers, host owns git/gh).

### Problem

Choose the backend that delivers a working "Final PRD → merge-ready PR" flow
fastest with the least new machinery, while keeping extension paths open.

### Alternatives

- **herdr** — agent-native (prompt/wait/lifecycle states, blocked-detection,
  reattach, session persistence) but its core value is local-machine
  persistence that ephemeral CI does not need; adopting it now means a new
  watcher + a pi-native worker runtime rewrite. Deferred as the local
  visibility/dev runtime.
- **Woodpecker** — self-hosted, container-native, no per-minute cost, but needs
  a server + agent + GitHub OAuth app + webhook reachability and a workflow
  syntax port. Deferred as the self-hosted upgrade path.

### Decision

GitHub Actions hosted runners (`ubuntu-latest`) now. The only new artifacts are
a `--headless` mode on `bin/factory-run.sh` and a workflow file. The worker
stays in the existing sandbox container; the container runtime on the runner is
docker via the driver's `IMPLEMENTER_PODMAN_BIN` seam (docker ships on hosted
runners).

### Rationale

Least new machinery (YAGNI): the drivers are the hard part and are done. The
free allowance (2,000 private-repo minutes/month) covers the expected task
cadence. The loop logic lives in the script, not the YAML, so porting to
Woodpecker later is a thin rewrite, and herdr remains the local runtime for the
same loop.

### Consequences

- Hosted-runner constraints: 6h job cap (loop must be bounded), ephemeral
  per-run setup, PAT required for cross-repo PRs (`GITHUB_TOKEN` is
  single-repo), `docs/prd-queue/**` path-filter trigger.
- herdr/Woodpecker stay documented extension paths, not built.
- The task stays Medium; the "agent containerisation (all)" line is satisfied
  by the existing sandboxed workers + the portable (env-driven, seam-based)
  host loop.

### Revision triggers

- Free-minute allowance exhausted by the loop's cadence.
- A loop needs more than the 6h hosted-runner cap.
- The thermisticles/cloud move lands (workspace-portability tasks) and
  self-hosted execution becomes natural (→ Woodpecker self-hosted or herdr
  persistent host).
