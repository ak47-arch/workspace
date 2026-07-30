## Decision: Task-Centric Reference Hub

**Status**: accepted
**Date**: 2026-07-30
**Task**: end-to-end-traceability
**Project**: software-factory
**Session**: sessions/019fb3ee-9573-78d2-9d4b-a4bf49a742a7/session.jsonl

### Context

Artifacts for a single task (PRD, analysis sessions, implementation sessions, decisions) are scattered across multiple directories: `docs/prd-queue/`, `docs/knowledge/sessions/<uuid>/`, `docs/knowledge/sessions/<uuid>/decisions/`. There was no single place to find everything related to a task.

### Problem

Opening a task requires knowing which directories to search and which session UUIDs are relevant. The knowledge is tacit — it lives in the agent's memory or the user's recall, not in the workspace structure.

### Alternatives

1. **Task directory with copies** (`docs/tasks/<slug>/` containing everything). Rejected: session files are large (200KB-1MB+) and copying them wastes space and creates sync issues when the canonical session grows. Sessions can also span multiple tasks, making duplication awkward.
2. **Reference hub file** (chosen) — a single lightweight Markdown file at `docs/tasks/<slug>.md` containing links to all artifacts. Artifacts remain in their canonical locations. No copies, no sync problems.

### Decision

The task file at `docs/tasks/<slug>.md` is the reference hub. It contains:
- `**Status**`: current lifecycle state
- `**Project**`: the project the task belongs to
- `**Created**` / `**Completed**`: dates
- `## Artifacts`: links to PRD, analysis session, implementation session, verification session
- `## Sessions`: links to all session.jsonl files involved
- `## Decisions`: links to all decision files

Artifacts are never copied into the task directory — they live in their canonical locations and are referenced by path.

### Rationale

- Single source of truth — the session file lives in one place, the PRD lives in one place
- Lightweight — one small file per task, no duplication
- Sessions can span multiple tasks — just list the same session UUID in both task files
- Easy to backfill — existing completed tasks just need a single `.md` file created
- Grep-friendly — `rg "Task: slug"` finds everything, and the task file is the entry point

### Consequences

- Creating a task file when a task is picked up is now a required step in the product-layer workflow
- The task file must be kept in sync with the task's lifecycle (status changes, new sessions added)
- No existing tooling needs to change — the task file is additive, not a replacement for anything

### Revision triggers

- If the number of tasks grows large enough that a flat directory becomes unwieldy
- If a task dashboard or CLI tool is added that needs a more structured format (could evolve to YAML frontmatter or JSON)