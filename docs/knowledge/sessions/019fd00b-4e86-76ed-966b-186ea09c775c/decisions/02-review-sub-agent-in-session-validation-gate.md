## Decision: Review Sub-Agent as In-Session PRD Verification Gate

**Status**: accepted
**Date**: 2026-08-05 09:22
**Task**: [extend-pm-assembly-line](../../../../tasks/extend-pm-assembly-line.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The PRD verification gate is a read-only review sub-agent spawned inside the product-layer session.

### Context

The factory needs a verification gate so only high-quality PRDs move to autonomous implementation. Earlier in the session this was framed as a CI pipeline: a transition script invoked in a GitHub Actions flow that runs a verification gate and, on success, moves the PRD to in-progress.

The turn to a sub-agent came from two observations: (1) a CI round-trip is asynchronous — the PRD returns cold, often after the user has moved on and lost the design context; (2) an in-session gate runs while the user is actively working in the product layer, when the design is warm.

pi (via the subagent extension in `opensource/pi-mono/packages/coding-agent/examples/extensions/subagent`) can spawn isolated sub-process agents with delegated system prompts and restricted tool sets — including a `reviewer` profile that is read-only by instruction.

### Problem

Where should the PRD verification gate run so that it is effective, low-infra, and forces quality review while the user's product-layer context is still fresh?

### Alternatives

- **CI pipeline gate**: a transition script invoked in GitHub Actions that validates and transitions. Rejected for this part — async round-trip loses context, adds CI infrastructure to manage, and the quality discussion is coldest exactly when the user is most needed.
- **A separate review agent / plugin framework**: build a checks-directory + runner + manifest to make checks extensible. Rejected — an agent is inherently extensible; a plugin framework is ceremony.
- **In-session read-only review sub-agent (chosen)**: the product-layer agent spawns a read-only review sub-agent inside the same session that runs checks and returns a report.

### Decision

The PRD verification gate is a **read-only review sub-agent** spawned inside the product-layer session. It:
- Has **no code or context modification privileges** — it only reads the PRD and codebase, runs tests/analysis, and produces a report.
- Runs **deterministic checks** (mechanical: header fields, required sections per category, file map, verification commands, context pointers, tasks.txt ↔ task file consistency, unique slugs, linked sessions/decisions).
- Runs **non-deterministic checks** (judgment: is the PRD truly self-contained, are user stories independently checkable, do implementation decisions resolve ambiguities, would an agent with only this PRD + context engine know what to build).
- Produces a structured **report** separating blocking vs advisory findings.
- On gate failure, control returns to the product layer: the report becomes the agenda for a deliberation with the user, the PRD + decisions are updated, and the review is re-spawned. This in-session feedback loop is the mechanism that sharpens context before implementation.
- On pass, the task transitions to `in-progress` in the same session **with the user's blessing**, the report attached to the task file as evidence.

Extensibility is a property of the agent: adding a check = adding a rule to its instructions/skill or a script it runs — no pipeline change.

### Rationale

- Context freshness: runs while the user is actively working, capturing the review bottleneck #1 (requirements + technical decisions clear) when value is highest.
- Asymmetric privilege is safe by construction: review reads, implementation writes.
- Zero CI infrastructure to manage for this part; the agent is the container for both deterministic and non-deterministic checks.
- The review sub-agent's read-only, report-and-assess shape is reusable later for the code-review bottleneck (#2).

### Consequences

- A review agent profile/skill must be created (an agent definition, not CI).
- The product-layer workflow gains a review step (spawn review → act on report → re-spawn until pass).
- The task transitions to `in-progress` happen in-session with user blessing; gate report is evidence in the task file.
- The task state machine may need a visible `prd-revision` state so repeated gates are auditable.

### Revision triggers

- The gate proves insufficiently strict in practice (poor PRDs still reach implementation), requiring automated/CI enforcement or a human sign-off layer.
- pi's subagent mechanism is not available or not installable as expected, forcing a fallback (CI or in-session manual checklist).
- The review sub-agent's privileged model can be enforced reliably enough to trust for write-scoped stages.
