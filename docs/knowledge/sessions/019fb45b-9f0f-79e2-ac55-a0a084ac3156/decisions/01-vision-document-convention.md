## Decision: Vision Document Convention for Upstream Traceability

**Status**: accepted
**Date**: 2026-07-31 01:21
**Task**: _(none — part of the ongoing context infrastructure initiative)_
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Adopt the docs/vision/ convention as defined in docs/vision-convention.md

### Context

The progressive disclosure context engine was missing its upstream link. The chain was: AGENTS.md → factory-context.md → tasks → PRDs → sessions → decisions. But there was no standard way to capture **why a project exists** and **where it's headed** — the vision layer that should sit between factory-context.md and task files.

Two vision docs existed (survival-infrastructure VISION.md and TECHNICAL_VISION.md, and legacy feed_analyser archive/vision.md) but they used different paths, different formats, and had no standard way to link to tasks or be referenced from tasks. The factory-context.md Vision table was incomplete and inconsistent.

The downstream traceability (task → PRD → sessions → decisions) was already solved by the `end-to-end-traceability` task. What remained was the upstream traceability: vision → tasks.

### Problem

How should vision docs be structured, where should they live, and how should they connect to the existing task traceability chain so that an agent can discover purpose context efficiently?

Specifically:

1. **No standard path** — surviving vision docs lived at `docs/technical/` (survival-infrastructure) and `archive/` (feed_analyser). New projects had no convention to follow.
2. **No standard format** — survival-infrastructure's VISION.md was comprehensive but had no template for new projects. The legacy feed_analyser vision was a free-form document.
3. **No link to tasks** — vision docs had no way to reference active work. Task files had no way to reference their originating vision.
4. **No link in PRDs** — PRDs described solutions but had no field to connect back to the project vision.

### Alternatives

1. **Centralized vision directory** (`docs/vision/<project>.md`) — All vision docs in one place. Rejected because it separates vision from the project it describes, making it harder for agents working inside a project directory to find context.

2. **No formal convention** — Let each project evolve its own style. Rejected because inconsistency would make the progressive disclosure chain unreliable — an agent couldn't predict where or how to find vision context.

3. **Adopt survival-infrastructure's existing pattern** (`docs/technical/VISION.md`) — Rejected because `docs/technical/` conflates stakeholder vision with technical implementation. The two-doc split (VISION.md vs TECHNICAL_VISION.md) is valuable, but the path should be `docs/vision/` to signal intent.

4. **Single VISION.md for all projects** — Rejected because complex projects (like survival-infrastructure) need separate stakeholder and technical vision documents to avoid mixing mission language with implementation planning.

### Decision

Adopt the `docs/vision/` convention as defined in `docs/vision-convention.md`:

- **Path**: `<project>/docs/vision/VISION.md` (required) + `TECHNICAL_VISION.md` (optional for complex projects)
- **Format**: Standard 9-section template (Why This Exists, Core Intent, Architecture Overview, Scope Boundaries, Guiding Principles, Active Tasks, Future Direction, A Living Vision)
- **Linking**: Three-way link between vision docs, task files (`**Vision**:` field), and PRDs (`**Vision**:` field)
- **Maintenance**: Vision docs are stable by design — updated only when purpose or direction meaningfully changes

### Rationale

- **Progressive by design**: An agent reads factory-context.md → finds the vision doc link → reads the vision → finds active tasks → reads tasks → finds PRDs → sessions → decisions. Each layer is a narrows.
- **Project-local**: Vision docs live inside the project they describe, so agents working in the project directory find them naturally.
- **Two-doc split**: Separates stakeholder intent from technical implementation, preventing mission creep in architecture discussions.
- **Linked but decoupled**: Vision docs reference tasks, but tasks don't require vision docs to exist. The link is an optional enrichment, not a hard dependency.
- **Quality over quantity**: The convention explicitly says "a boilerplate vision doc is worse than no vision doc" — preventing empty formalism.

### Consequences

- **Easier**: Agents can now discover why a project exists by following a predictable path from factory-context.md → vision doc → active tasks.
- **Easier**: New projects get a clear template for documenting purpose and direction.
- **Easier**: The upstream traceability chain is now complete (vision → tasks → PRDs → sessions → decisions).
- **Harder**: Existing projects without vision docs (llm, capture, workspace-portability, headroom-pi) need them written.
- **Harder**: Legacy vision docs at non-standard paths (survival-infrastructure's `docs/technical/`) are grandfathered in but create a minor inconsistency.
- **Changed**: The `save-knowledge` skill template now includes `Project:` field, and `docs/knowledge/index.md` is organized by project.

### Revision triggers

- If a project becomes complex enough that its single VISION.md is too long, consider splitting into VISION.md + TECHNICAL_VISION.md.
- If the convention proves too rigid (projects skip it or write boilerplate), consider relaxing the format requirements.
- If the `docs/vision/` path proves confusing (agents look in `docs/` root instead), add a symlink or redirect note.
