## Decision: Backend delivers a merge-ready PR; merge stays human

**Status**: accepted
**Date**: 2026-08-17 02:56
**Task**: [headless-agent-containerisation](../../../../tasks/headless-agent-containerisation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The backend loop stops at review success (APPROVE).

### Context

Existing authority-split decisions keep merging human-gated: the code-review
agent never merges (decision 05), and `bin/merge-pr.sh` is the only
master-pusher (decision 07). The PRD lifecycle requires the task to reach
`complete` only after UAT passes and the user explicitly gives the go-ahead. The
new headless backend host automates everything upstream of review success.

### Problem

Where exactly does the automated loop end? "Everything is done in the backend"
could be read as including the merge, but merging without UAT and explicit user
sign-off contradicts the lifecycle gate and the authority-split decisions.

### Alternatives

- **Backend merges on APPROVE** — rejected: violates decisions 05/07, removes
  the UAT gate, and bypasses the explicit go-ahead the lifecycle requires.
- **Backend merges into a staging/develop branch** — rejected as
  over-engineering; not requested and adds a branch topology the factory does
  not have.

### Decision

The backend loop stops at review success (`APPROVE`). The deliverable is a
**merge-ready PR**: implemented, reviewed, approved, and labelled so the user
**Summary**: ## Decision: Backend delivers a merge-ready PR; merge stays human Status: accepted Date: 2026-08-17 02:56 Task: headless-agent-containerisation Project: software-factory
can merge it directly. The task transitions to `in-review`. The user performs
UAT on the PR and runs `bin/merge-pr.sh` (decision 07) to merge and complete
the task.

### Rationale

Preserves the authority split and the "user explicitly signed off" gate while
giving the user exactly the promised experience: concern yourself with the task
until the PRD is Final, then receive a reviewed, mergeable PR. The user touches
the task at exactly two points — writing the Final PRD, and merging the
deliverable.

### Consequences

- The backend host never runs `gh pr merge`; no master push from the loop.
- The task ends the loop at `in-review`; UAT happens at merge time.
- `merge-pr.sh` remains the only master-pusher; the PRD moves to
  `docs/prd-archive/` only when the task completes.

### Revision triggers

- The user later wants autonomous merge for trusted low-risk tasks.
- A workflow emerges where UAT must happen before review, not at merge.
