## Decision: Operator merge-tool — authority-split enforced by tooling + container

**Status**: accepted
**Date**: 2026-08-14 17:28
**Task**: [code-review-agent](../../../../tasks/code-review-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Introduce bin/merge-pr.sh as the sole operator-side merge tool (human-Gated, UAT-triggered).

### Context

Decision 05 established that the code-review agent **never merges** — merge is a
human-gated operator action. As part of automating task-level PR tracking
(decision 06), a natural temptation was to let the review driver perform the
merge. That would have collapsed the authority split and defeated the human-UAT
gate, so the merge action was instead wrapped in a dedicated operator-side tool.

### Problem

With the review driver now appending a "Review" row to the task file on every
delivery, the constraint from decision 05 needed a concrete, mechanical form:
who precisely runs the merge, how the Merge row gets onto the task file, and how
we guarantee (not just hope) that the autonomous reviewer can never merge.

### Alternatives

- **Let the review driver merge on APPROVE.** Rejected — collapses the
  authority split; no human UAT between "review passed" and "shipped".
- **Reuse `gh pr merge` inline from operator one-liners.** Rejected — every
  operator merge would require hand-editing the task file to keep decision-06
  tracking accurate (error-prone, untracked).
- **`bin/merge-pr.sh` as a standalone operator tool.** Chosen — the merge is
  *only* reachable via a human-invoked script, and its side-effect is the
  canonical Merge row.

### Decision

Introduce **`bin/merge-pr.sh`** as the sole operator-side merge tool (human-Gated,
UAT-triggered). It `gh pr merge --merge`s the PR, derives the task slug from the
PR title (`[factory] <slug>: …`), appends the `Merge:` row to the task file
(idempotent, decision-06 schema, from `lib-pr-tracking.sh`), commits that update,
and pushes master. Supports `--dry-run`. The autonomous review driver
(`bin/review-run.sh`) carries **no merge path and no reference to merge-pr.sh**.

Physical enforcement is layered too: the review worker runs in a container with
**no `gh` binary** and a **read-only `/workspace`**, so it cannot mutate the
**Summary**: ## Decision: Operator merge-tool — authority-split enforced by tooling + container Status: accepted Date: 2026-08-14 17:28 Task: code-review-agent Project: software-facto
workspace or issue a GitHub merge even if instructed to.

### Rationale

The split must be **mechanical, not conventional** — a future agent should not
have to "remember" decision 05. Centralizing the merge in one operator tool makes
the human-gated action discoverable, auditable (Merge row with SHA/actor/date),
and the only push-to-master path in the factory. Keeping the reviewer merge-less
in both code and runtime preserves the user's explicit UAT go-ahead as the true
release authority.

### Consequences

- Each merged PR yields a complete, joinable record: PR → review → merge (decision
  06), enabling the evaluation pass to attribute the full chain per task.
- Only `bin/merge-pr.sh` pushes master today; reviewer/implementer commit locally
  and leave master un-pushed until an operator merges. This asymmetry is
  deliberate but should be re-confirmed if full auto-deploy is ever desired.
- Merge authority now depends on *someone running the manual tool* — operations
  should document the per-PR human runbook (review → UAT → merge-pr).

### Revision triggers

- If a decision is made to move to fully automatic merging/shipping on APPROVE,
  this decision is superseded (that is a deliberate, user-authored change, not an
  accident to be defaulted into).
- If container guardrails (no `gh`, read-only `/workspace`) are relaxed,
  re-verify the no-merge path at runtime, not just in source.
- If a second party (e.g. an operator bot) gains merge capability, reconcile the
  authority split in the PR-tracking schema.
