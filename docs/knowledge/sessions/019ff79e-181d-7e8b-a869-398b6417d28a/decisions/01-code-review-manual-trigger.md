## Decision: Code-review agent uses a manual trigger (no polling infra)

**Status**: accepted
**Date**: 2026-08-13 23:00
**Task**: [code-review-agent](../../../../tasks/code-review-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: V1 is a manual, user-invoked pipeline exactly mirroring the implementer: bin/review-run.sh <pr> (plus --pick and --dry-run).

### Context

Designing the post-implementation code-review agent, the user explicitly wants
reviews to be picked up by an agent — not performed by hand by them (as happened
for PR #1 `extension-inline-agent`). A full polling/webhook design (systemd timer +
GitHub status claims + reviewed-SHA dedupe) was drafted first, mirroring CI-style
serialization.

### Problem

The user rejected the polling infrastructure as unnecessary at this stage. The
requirement is a review agent **triggerable manually like the implementer agent**,
reusing the same infrastructure pattern — no new always-on machinery.

### Alternatives

- **Label + host poller** (systemd timer, status-based claim, SHA dedupe) — robust
  against concurrency and re-review churn, but adds an always-on scheduler and
  claim protocol the factory doesn't need yet. Rejected as premature
  (assembly_line is deliberately YAGNI).
- **GitHub Actions webhook → host dispatch** — needs a self-hosted runner or a
  reachable host endpoint and must reach podman; too heavy for the stage. Rejected.
- **Implementer chains the reviewer after `gh pr create`** — zero infra but
  conflates build and review into one long-running unit and can't cover non-factory
  PRs. Deferred; decoupling preferred.

### Decision

V1 is a manual, user-invoked pipeline exactly mirroring the implementer:
`bin/review-run.sh <pr>` (plus `--pick` and `--dry-run`). No timer, no webhook, no
status-claim protocol. The implementer **will tag** PRs `factory:needs-review` at
create time (a one-line `--label` addition, see the PRD file-map) as **inert
metadata** — it costs one line, makes `--pick` work, and keeps the seam open for
future automation without building the automation now.

### Rationale

The user's explicit call; matches the factory's YAGNI discipline (assembly_line is
the least-developed component). The label is a cheap forward-compatible hook, and
the driver's selection logic (`--pick`) is a thin seam that a poller can wrap
later without touching the worker.

### Consequences

- Review latency becomes manual (operator invokes the driver) — acceptable for a
  personal factory with one or two PRs in flight.
- Concurrency/dedupe robustness work is deferred until automation is added.
- `--pick` depends on the `factory:needs-review` label being present on PRs.

### Revision triggers

- Multiple concurrent PRs needing review make the manual trigger tedious → revisit
  poller/webhook.
- Non-factory (user-authored) PRs need routine review → add webhook or
  label-based poller.
- The factory grows a real CI runner (assembly_line staffing) → reviews belong in CI.
