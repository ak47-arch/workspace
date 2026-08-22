## Decision: PRD as Routing Document, Context Engine Provides Depth

**Status**: accepted
**Date**: 2026-08-05 09:22
**Task**: [extend-pm-assembly-line](../../../../tasks/extend-pm-assembly-line.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The PRD is a routing document, not a monolith.

### Context

The factory is designing the downstream flow from a completed PRD to autonomous implementation. A central tension emerged in grilling: how much of the implementation detail must a PRD contain for an agent to pick it up and implement end-to-end with no user interaction?

The naive answer — the PRD must be a self-contained monolith containing everything — would bloat the document and duplicate the context engine. But a too-thin PRD would force the implementation agent to hunt and improvise.

The workspace already has a purpose-built context engine (the infrastructure spine) with a progressive disclosure chain: AGENTS.md → factory-context.md → discovery layer (OpenWiki, vision docs, PRDs, skills) → knowledge base (decisions, session traces). The `extract-context` utility can even reconstruct the exact planning context window from a saved `session.jsonl` using pi's own session manager.

### Problem

How to make a PRD sufficient for autonomous implementation without making it a bloated monolith — i.e., where is the line between "the PRD must contain everything" and "the agent discovers on its own"?

### Alternatives

- **PRD as self-contained monolith**: contain every implementation detail (signatures, file contents, types). Rejected — bloats the doc, duplicates the context engine, makes PRD authoring burdensome, and fights the factory's own progressive-disclosure philosophy.

- **PRD as routing document + context engine depth (chosen)**: the PRD is authoritative on scope, location, and acceptance; the context engine provides depth on demand.

### Decision

The PRD is a **routing document**, not a monolith. It becomes the entry point of the implementation session's progressive disclosure chain, authoritative on:
- **Scope / problem / solution** (what to build and why)
- **Location** — a file-level map of where the change lands
- **Acceptance** — verification commands and checkable user stories
- **Boundaries** — what not to touch (out-of-scope + explicit)

And it carries **context pointers** into the context engine's layers: relevant OpenWiki pages (code structure), vision docs (why), decision records (design intent), and the session trace (full planning conversation via `extract-context`).

The implementation agent is authoritative on **mechanics** (exact API signatures, library idioms, existing patterns) — discovered via the disclosure chain, which it's already good at.

### Rationale

- Keeps PRDs lean while making them self-contained in the operational sense: the PRD alone is a sufficient *entry point*, from which the agent can navigate to everything it needs without asking the user.
- Reuses the context engine rather than fighting it — the engine was built precisely for efficient agentic search.
- The agent never needs to ask *what to build*, only figure out *how to build it* — which it can resolve from context.

### Consequences

- PRD template gains a "file map" section, a "verification commands" section, and explicit context pointers.
- The implementation pickup protocol reads: read PRD → follow context pointers → implement → verify → raise PR.
- PRD authoring (product-layer grill) must produce these routing sections; the review gate checks for them.

### Revision triggers

- The context engine changes such that the disclosure chain no longer routes efficiently for an autonomous agent.
- A task category (Medium/Large) proves to need concrete Program Design content that the routing-document model under-provides.
