## Decision: Semantic similarity assessment with partial-split support

**Status**: accepted
**Date**: 2026-08-16 23:49
**Task**: task-pickup-similarity-merge
**Project**: software-factory
**Session**: sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/session.jsonl

### Context

The product-layer skill will propose similar tasks when a task is picked up. The user made clear the process must not be a mechanical one-shot merge detector: the agent should propose candidate tasks, then work with the user to establish the **degree** of similarity, because some tasks are only partially similar.

### Problem

Tasks are rarely binary same/different. A picked task may share only part of its scope with another task. Ignoring partial similarity either merges unrelated work or leaves a mergeable portion on the table.

### Alternatives

- **Keyword/fuzzy matching with thresholds** — rejected: "obviously semantic judgement" per the user; no scoring thresholds, no embeddings, no fuzzy-match libraries.
- **Binary merge decision only** — rejected: fails the partial-similarity case the user explicitly raised.
- **Collaborative degree-of-similarity assessment with partial split** — accepted.

### Decision

The agent proposes candidate similar tasks with a one-line "why" for each (semantic judgment over subject + action + project context; three match classes: near-duplicate, same-subject-different-framing, cross-project capability). The agent and user then establish the degree of similarity per candidate:

- **Full** → merge into one task file + one PRD, closed together.
- **Partial** → divide the picked task: the overlapping part joins the bundle; the remainder becomes a separate task.
- **None** → proceed with the single task.

The takeaway: the conversation generates clarity — the bundle and any split pieces end up sharper than the original entries. No automatic merging; always user-confirmed.

### Rationale

The user's explicit direction: "the agent should work with the user to get generate more clarity." This makes the check a clarification engine rather than a merge detector, and avoids both over-engineering (no scoring infra) and under-capturing (partial splits).

### Consequences

- Product-layer skill's pick-up flow gains a collaborative similarity-assessment phase.
- Partial splits produce a new pending task line for the remainder (see decision 03).
- Every proposal carries a "why" line so the user can veto quickly.

### Revision triggers

- If the volume of candidates grows so large that the "why" list becomes unwieldy, a ranking or grouping rule may be needed.
