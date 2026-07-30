## Decision: Task Identification

**Status**: accepted
**Date**: 2026-07-30
**Task**: end-to-end-traceability
**Project**: software-factory
**Session**: sessions/019fb3ee-9573-78d2-9d4b-a4bf49a742a7/session.jsonl

### Context

The software factory tracks tasks in `docs/tasks.txt` and produces artifacts (PRDs, sessions, decisions) across multiple directories. Previously, there was no stable identifier linking a task to its downstream artifacts — they were connected only by convention and human memory.

### Problem

Without a task identifier that appears in every artifact, traceability is effortful. You have to know which sessions and PRDs relate to which task, and the knowledge is lost between sessions.

### Alternatives

1. **UUID v7** — time-ordered UUID like existing session IDs. Rejected: unwieldy for human reference in conversation and file listings.
2. **Sequential counter (TASK-001)** — simple, human-readable. Rejected: adds global numbering state that must be maintained, and the number gives no semantic information.
3. **Human-readable slug** (chosen) — a short, descriptive identifier derived from the task title at creation time (e.g. `github-browser-auth-flow`). No numbering state, grep-friendly, conversational.

### Decision

Task identifier is a **human-readable slug** derived from the task title. The slug is set when the task is first picked up by the product-layer skill. It appears in:
- The task file path: `docs/tasks/<slug>.md`
- The PRD header: `**Task**: <slug>`
- Decision files: `**Task**: <slug>`
- The PRD filename: `docs/prd-queue/<date>-<slug>.md`

### Rationale

- Slugs are conversational — you can say "the GitHub auth task" and it maps directly to `github-browser-auth-flow`
- Grep-friendly — `rg "Task: github-browser-auth-flow"` finds every artifact
- No state to maintain — slugs are derived from titles, not from a counter
- Consistent with existing conventions — PRD filenames and decision slugs already follow this pattern

### Consequences

- Tasks must have a title that can be meaningfully slugged
- The slug must be unique across the task list (enforced at creation time by the agent)
- No change to the existing `tasks.txt` format — tasks are still listed there; the slug is created only when the task is picked up

### Revision triggers

- If the number of tasks grows large enough that slug collision becomes a practical problem
- If a machine-readable identifier (e.g. for API integration) becomes necessary