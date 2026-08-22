## Decision: Headless backend host takes over once a PRD is Final

**Status**: accepted
**Date**: 2026-08-17 02:56
**Task**: [headless-agent-containerisation](../../../../tasks/headless-agent-containerisation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Once a PRD is Final (task prd-ready), a headless backend host takes over autonomously: it picks up the PRD, runs the implementer (container, separate worktree), runs the

### Context

The factory's implementer and reviewer run on a brain+hands pattern: a headless
`pi` worker inside a podman sandbox container implements/reviews, while a host
driver (`bin/implementer-run.sh`, `bin/review-run.sh`) owns all git and all
`gh` calls. `bin/factory-run.sh` chains them back-to-back, but it is
manual-trigger, has an interactive UAT gate between the stages, and is
single-shot — no polling of `docs/prd-queue/`, no unattended revise loop. The
host role is effectively played inside the user's interactive session: the TUI
blocks for the whole run, and on REQUEST_CHANGES the user must re-run drivers by
hand.

### Problem

The user must stay involved through the whole implement → review → revise loop.
The stated goal: involvement ends the moment the PRD reaches **Final** status.
Everything downstream — implementation, review, revision iterations — must run
in the backend, unattended, and the user should only ever receive the finished
deliverable.

### Alternatives

- **Keep the manual chain, add only a revise helper** — rejected: still requires
  the user to kick each stage and answer the UAT gate.
- **Human approval gate per loop iteration** — rejected: the user explicitly
  wants zero interaction until the deliverable exists.
- **Full automation including merge** — rejected; the merge boundary is decided
  separately (see `02-merge-ready-deliverable`).

### Decision

Once a PRD is **Final** (task `prd-ready`), a headless backend host takes over
autonomously: it picks up the PRD, runs the implementer (container, separate
worktree), runs the reviewer on the raised PR, and on `REQUEST_CHANGES` runs
`implementer-run.sh --revise` → re-review, looping until review success
(`APPROVE`) or a stop condition. The user's only remaining involvement is the
merge-ready PR.

### Rationale

Matches the stated goal directly; builds on the existing drivers
(`implementer-run.sh --pick/--revise`, `review-run.sh --pick`) instead of
inventing new agents; removes the session-blocking and UAT-gate bottlenecks that
make the current chain manual.

### Consequences

- Implementer/reviewer drivers must be invocable with zero interactive stdin
  (the UAT gate in `factory-run.sh` moves after the loop, to merge time).
- The host needs a Final-PRD trigger (queue polling) and a stop condition for
  the revise loop (revision cap).
- The task lifecycle ends the loop at `in-review`; the PRD stays in the queue
  until the user merges and the task completes.

### Revision triggers

- Review success cannot be reached reliably within the revision cap.
- The user wants mid-loop input (e.g. blocking findings surfaced immediately).
- The Final-PRD trigger proves unreliable (missed PRDs).
