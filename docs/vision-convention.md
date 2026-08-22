# Vision Document Convention

This document defines how vision docs are structured, linked, and maintained across the workspace. It establishes the **upstream traceability link** between project vision and task-level work.

## 1. Purpose

Vision docs answer **why a project exists** and **where it is headed**. They are the first layer an agent reads when entering a project context, before diving into tasks, PRDs, or decisions.

A good vision doc is:
- **Concise** — a few paragraphs, not a novel
- **Stable** — changes infrequently, only when direction shifts
- **Connected** — links to active tasks so the reader can find current work

A boilerplate vision doc is worse than no vision doc. Only write one when the project has enough substance to merit it.

## 2. Path Convention

Every project gets a `docs/vision/` directory at its root:

```
<project>/
├── docs/
│   └── vision/
│       ├── VISION.md              # Required — stakeholder vision
│       └── TECHNICAL_VISION.md    # Optional — technical roadmap
```

### When to use two docs

| Layer | File | Content |
|-------|------|---------|
| **Stakeholder Vision** | `VISION.md` | Why it exists, core intent, guiding principles, scope boundaries, active tasks |
| **Technical Vision** | `TECHNICAL_VISION.md` | Architecture direction, data model, phased roadmap, implementation constraints |

Use both when the project is complex enough that stakeholder intent and technical implementation need separate treatment. For simple projects, a single `VISION.md` is sufficient.

### Legacy projects

Projects that already have vision docs at different paths (e.g. `survival-infrastructure/docs/technical/VISION.md`) may keep their existing location. New projects follow the `docs/vision/` convention.

## 3. VISION.md Format

```markdown
# <Project Name> Vision

## Why This Exists

The problem or motivation that justifies this project. What happens without it?

## Core Intent

What this project aims to be. A single paragraph that captures the essence.

## Architecture Overview

High-level structure. How the pieces fit together. Keep it to 3-5 sentences or a simple diagram.

## Scope Boundaries

What this project is NOT. Explicitly guards against scope creep.

### This project is:
- <characteristic>
- <characteristic>

### This project is not:
- <exclusion>
- <exclusion>

## Guiding Principles

Design tenets that shape decisions. 3-5 principles max.

## Active Tasks

Links to task files for work that advances this vision. Keeps the vision connected to current execution.

- [<task-slug>](docs/tasks/<task-slug>.md) — <one-line description>
- [<task-slug>](docs/tasks/<task-slug>.md) — <one-line description>

## Future Direction

Where this project is headed. High-level, not a roadmap. Signals what to plan for.

## A Living Vision

This document defines intent and direction, not frozen implementation details. Update it when the project's purpose or scope meaningfully changes.
```

## 4. TECHNICAL_VISION.md Format

```markdown
# <Project Name> Technical Vision

## Purpose

What this document covers and who it's for.

## Architecture Direction

Key architectural decisions, data flow, and structural boundaries.

## Phased Roadmap

Implementation phases, each with a clear goal. Mark completed phases as `(implemented)` and deferred phases as `(deferred)`.

## Readiness Gates

Conditions that must be met before advancing to the next phase.

## Non-Goals

What is explicitly out of scope for the current technical direction.
```

## 5. Linking Convention

Three link types connect vision to the task traceability chain:

### Vision → Tasks

In `VISION.md`, the `## Active Tasks` section lists task slugs with links to their task files. This tells the agent what work is currently advancing the vision.

```markdown
## Active Tasks

- [gdrive-instruction-source-ingest](docs/tasks/gdrive-instruction-source-ingest.md) — Add GDrive as an instruction source for the survival-infrastructure pipeline
- [audio-event-ingestion](docs/tasks/audio-event-ingestion.md) — Add whisper.cpp transcription pipeline
```

### Tasks → Vision

In task files (`docs/tasks/<slug>.md`), add a `**Vision**:` field to the header:

```markdown
# Task: <slug>

**Status**: active | complete | deferred
**Project**: <project-slug>
**Vision**: <project>/docs/vision/VISION.md
**Created**: <yyyy-mm-dd>
```

If the project has both VISION.md and TECHNICAL_VISION.md:

```markdown
**Vision**: <project>/docs/vision/VISION.md | <project>/docs/vision/TECHNICAL_VISION.md
```

### PRDs → Vision

In PRD headers (`docs/prd/<date>-<slug>.md`), add a `**Vision**:` field:

```markdown
# PRD: <title>

**Date**: <yyyy-mm-dd>
**Status**: Draft | In Review | Approved | Implemented
**Project**: <project-slug>
**Vision**: <project>/docs/vision/VISION.md
**Session**: <path>
```

## 6. factory-context.md

The Vision/Design Intent table in `docs/factory-context.md` should list every active project with its vision doc path. Update it when a new vision doc is created or when a project's status changes.

## 7. When to Write a Vision Doc

Write a VISION.md when:

1. A project has enough substance that an agent needs **purpose context** to make good decisions
2. A project has queued or active tasks that benefit from understanding the larger direction
3. A project is complex enough that its scope boundaries need explicit documentation

A project with no active tasks, no PRDs, and no agent traffic does not need a vision doc.

## 8. Maintenance

- Vision docs are stable by design. Update them only when the project's purpose, scope, or direction meaningfully changes.
- When adding a new task, check if the vision doc's `## Active Tasks` section should include it.
- When completing a task, decide whether to keep or remove it from `## Active Tasks`. Completed tasks that were part of the core vision may stay as historical reference.