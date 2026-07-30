## Decision: Traceability Links via Task Field

**Status**: accepted
**Date**: 2026-07-30
**Task**: end-to-end-traceability
**Session**: sessions/019fb3ee-9573-78d2-9d4b-a4bf49a742a7/session.jsonl

### Context

Every artifact in the software factory (tasks, PRDs, sessions, decisions) needs to be connected so the full lifecycle of a task can be traced. Previously, artifacts were connected only by convention — the PRD session was mentioned in the PRD header, but there was no way to discover all artifacts for a given task.

### Problem

Tracing a task from entry to completion required knowing which directories to search and which session UUIDs were involved. The connections existed in the agent's session memory but were not durable in the workspace.

### Alternatives

1. **Centralised registry file** — a single `traceability.json` or `manifest.md` listing all tasks and their artifacts. Rejected: creates a single point of contention and a maintenance burden every time an artifact is created.
2. **Database or CLI tool** — overengineered for the current scale. Rejected: too much infrastructure for a workspace that's still evolving.
3. **Task field in each artifact** (chosen) — every artifact (PRD, decision file) includes a `**Task**: <slug>` field in its header. The task file at `docs/tasks/<slug>.md` is the hub that lists all artifact paths. Discoverability is via `rg "Task: <slug>"`.

### Decision

Every artifact includes a `**Task**: <slug>` field in its header metadata. Specifically:
- **PRD header**: `**Task**: <slug>` added after `**Owner**`
- **Decision files**: `**Task**: <slug>` added after `**Date**`
- **Task file**: lists all artifact paths in its `## Artifacts` and `## Sessions` sections

The full chain for a task is discovered by:
1. Opening `docs/tasks/<slug>.md` for the hub view
2. Or running `rg "Task: <slug>" docs/` for a complete artifact list

### Rationale

- Zero infrastructure — no registry files, databases, or scripts to maintain
- Every artifact is self-describing — open any file and you know which task it belongs to
- Grep is a universal query tool — no specialised tooling needed
- Backward compatible — existing PRDs and decisions can be updated with the Task field

### Consequences

- The product-layer skill and save-knowledge skill templates were updated to include the `Task:` field
- Existing completed PRDs and decisions were backfilled with the Task field
- The user or agent must remember to include the Task field when creating new artifacts (enforced by the skill templates)

### Revision triggers

- If the number of tasks grows large enough that grep becomes slow or unwieldy
- If a dashboard or automated tool needs structured traceability data (could evolve to a small JSON manifest derived from the task files)