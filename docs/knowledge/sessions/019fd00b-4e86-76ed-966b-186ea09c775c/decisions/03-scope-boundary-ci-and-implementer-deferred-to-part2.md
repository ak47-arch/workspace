## Decision: Scope Boundary — CI and Implementer Agent Deferred to Part 2 (Assembly Line)

**Status**: accepted
**Date**: 2026-08-05 09:22
**Task**: [extend-pm-assembly-line](../../../../tasks/extend-pm-assembly-line.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The current task covers Part 1 only: the PRD verification subsystem (in-session read-only review sub-agent, deterministic + non-deterministic checks, report contract, in-

### Context

The task "Extend project management and start work on the assembly line components" was decomposed during grilling into two connected parts: (1) the PRD verification gate and transition (project management — built largely on existing bookkeeping infrastructure), and (2) the autonomous implementation agent and its surrounding infrastructure (the assembly line — not started at all).

The long-term vision is fully automated pickup: a prd-ready PRD is picked up, implemented end-to-end, and a pull request raised, with no user interaction. Near-term, the review sub-agent gate (see decision `02-review-sub-agent-in-session-validation-gate`) handles verification; the implementer is a separate, later concern.

Early in the session, CI/CD (GitHub Actions) was discussed as a natural home for the transition and gate. On reflection it was determined that CI is more infrastructure to manage and its value belongs with the implementation stage, not the verification gate.

### Problem

Where do the boundaries fall for the current task — what is in scope for Part 1, and what belongs to Part 2 (the assembly line)?

### Alternatives

- **Build the CI gate now** (GitHub Actions transition + validation workflow). Rejected — async round-trip loses the user's warm context, adds CI infra to manage for a verification that a sub-agent does better in-session.
- **Include the implementer agent now**. Rejected — the implementer's infrastructure (skills, context, extensions) is implementation-specific and should be kept lean and separate; it is the next stage, out of scope for this task.
- **Defer CI + implementer to Part 2 (chosen)**.

### Decision

The current task covers **Part 1 only**: the PRD verification subsystem (in-session read-only review sub-agent, deterministic + non-deterministic checks, report contract, in-session feedback loop, `in-progress` transition with user blessing) and the supporting PRD-template changes (file map, verification commands, context pointers).

**Explicitly out of scope:**
**Summary**: ## Decision: Scope Boundary — CI and Implementer Agent Deferred to Part 2 (Assembly Line) Status: accepted Date: 2026-08-05 09:22 Task: extend-pm-assembly-line Project: s
- **CI/CD infrastructure** — deferred to the implementation stage (Part 2); may or may not be needed later based on requirements.
- **The autonomous implementation agent** — Part 2, the assembly line's first real component. Its infrastructure (skills, context, extensions) will be implementation-agent-specific to keep it lean.
- **Code review / verification of implementations** — review bottleneck #2, downstream, out of scope (though it may reuse the review sub-agent's shape).

The task ends at `in-progress` with a documented hook where the Part 2 implementation agent picks up.

### Rationale

- Keeps the task bounded and buildable: Part 1 is small and self-contained (project-management bookkeeping + one agent definition + template changes).
- Defers CI to where it earns its keep (implementation PR validation, code review) rather than forcing it in for the gate.
- Keeps the implementer lean and separate, matching the "two asymmetric agent profiles" principle (review reads, implementation writes).

### Consequences

- No `.github/workflows/` changes in this task.
- A clean handoff seam at `in-progress` is a requirement of Part 1, so Part 2 can attach without rework.
- The assembly line component begins with the review sub-agent (a read primitive); the implementer (write primitive) follows in a later task.

### Revision triggers

- Requirements emerge that make CI necessary for the verification gate itself (e.g., PRDs must be gated without a user present, or the sub-agent mechanism proves unavailable).
- Part 2 begins and finds the `in-progress` hook insufficient, requiring Part 1 changes retroactively.
