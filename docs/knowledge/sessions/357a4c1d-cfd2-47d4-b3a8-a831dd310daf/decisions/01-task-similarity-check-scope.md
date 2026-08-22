## Decision: Task similarity check scope and merge policy

**Status**: accepted
**Date**: 2026-08-16 23:49
**Task**: [task-pickup-similarity-merge](../../../../tasks/task-pickup-similarity-merge.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The similarity check scans all task lines across all projects and statuses, but the merge offer is only for Pending/Queued tasks.

### Context

The product-layer skill lets the user pick a task from `docs/tasks.txt` to work on. Tasks frequently exist in another form in the same project or in other projects, so the user asked the skill to check a picked task against existing tasks across projects and offer to pick similar ones together. The question arose whether the check should also consider tasks already in the pipeline (in-progress/in-review) or completed.

### Problem

Which task statuses should be scanned, and what should the agent do with each? Merging into a task already being worked on, or into a completed task, could create confusion and duplicate effort.

### Alternatives

- **Merge offers for every status** — rejected: picking up completed or in-flight tasks together makes no sense; one is already done, the other has active work in different sessions/PRs.
- **Skip non-Pending/Queued statuses entirely** — rejected: the check's purpose includes surfacing duplication; a user entering a duplicate of a completed task benefits from knowing it already exists.
- **Scan all, offer merge only for Pending/Queued, informational flags otherwise** — accepted: keeps the system simple while covering both halves of the user's intent.

### Decision

The similarity check scans **all task lines across all projects and statuses**, but the merge offer is **only for Pending/Queued tasks**. For in-progress/in-review tasks the agent flags "this looks like it's already being worked on" (informational, no merge). For Complete tasks the agent flags "this appears to already be done" (informational, lets the user skip a duplicate entry or reframe it as a follow-up).

### Rationale

The user's stated goal is to close more tasks at once by picking similar ones together — that only makes sense for tasks that have not started. Informational flags for the other statuses cost nothing, prevent duplicate entries, and avoid merging into moving work. Keeps the system from over-complicating.

### Consequences

- Product-layer skill gains a similarity-check step that scans all statuses.
- Merge bundles can only be formed from Pending/Queued tasks.
- Users get warned about duplicates of completed or in-flight work.

### Revision triggers

- If a task in in-progress/in-review is found to be genuinely stalled and restartable as part of a new bundle, the policy may need revisiting.
