# Software Factory — Architecture Decisions

Date: 2026-07-23
Session: sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/session.jsonl

---

## 1. Knowledge base as infrastructure layer

**Status**: accepted

### Context

The software factory has four components: knowledge_base, assembly_line, project_management, and product/architecture. The knowledge base's role was initially underspecified — it was just "memory layer." As we designed the factory architecture, it became clear that the knowledge base is the foundational primitive everything else depends on.

### Alternatives considered

- **Knowledge base as a peer component** — equal to assembly_line, project_management, etc. This was the initial model but it didn't capture that every other component reads from and writes to it.
- **No knowledge base** — just code + READMEs. This is what the workspace already had, but it was insufficient for agentic development because design intent (the "why") was invisible.

### Decision

The knowledge base is the **infrastructure layer** of the factory. All other components interact with it. It does not depend on any other component, so it can be improved independently as better technology emerges — knowledge bases are a new primitive data source and the space is evolving quickly.

### Rationale

Treating knowledge base as infrastructure rather than a peer component reflects its actual role: it's the shared memory that every layer reads and writes. This also makes it independently improvable — we can swap technology, change formats, or add new capabilities without touching any other component.

### Consequences

- The knowledge base must be designed with stable interfaces so other components can depend on it
- We can experiment with better storage/retrieval technology independently
- Other components are decoupled from knowledge base implementation details

### Revision triggers

- A fundamentally better knowledge base primitive emerges (vector store, graph db, etc.) that would change the architecture
- The factory model is restructured in a way that changes component dependencies

---

## 2. Product/architecture as UX layer — two artifact outputs

**Status**: accepted

### Context

The product/architecture component's role was unclear. It was described as "User Layer, integrates with knowledge_base" but what it actually does — its inputs, outputs, and boundaries — needed definition to build the factory incrementally.

### Alternatives considered

- **Product/architecture as a planning layer** that talks to project_management. This would couple it to downstream concerns, violating the "detached" property.
- **Product/architecture as a documentation layer** that only produces specs. This would miss the design-intent capture that makes the knowledge base valuable.
- **A single agent doing everything** (product, implementation, project tracking in one session). Rejected because session context would mix product decisions with implementation noise.

### Decision

The product/architecture layer is the **UX layer** — the only interface the user interacts with directly. It is completely detached from all other components; they don't need to know it exists.

It produces exactly **two durable artifacts**:
1. **PRD** — forward-looking spec, saved to `docs/prd-queue/`. Consumed asynchronously by downstream layers.
2. **Design decisions** — backward-looking structured records, saved to `docs/knowledge/`. Captured during the grilling process.

These artifacts accumulate in their respective directories and are picked up by project_management whenever it runs. No pipeline, no handoff mechanism — just two durable files in the repo.

### Rationale

Two artifacts cover both directions of time: the PRD says where we're going, the decisions say why we chose this path. Together they're sufficient for downstream layers to work without talking to the user. Keeping product/architecture detached means its prompt, skills, and session history stay pure — no cross-contamination from implementation or project tracking.

### Consequences

- The product layer can be built and iterated independently
- Session context is always clean product work
- Downstream layers consume static artifacts, making them testable in isolation
- Two artifacts is a minimal surface area — easy to change later

### Revision triggers

- The need for a third artifact type (e.g. a design document, an RFC) emerges from practice
- The PRD format proves insufficient for downstream consumption

---

## 3. Progressive disclosure chain for agent context

**Status**: accepted

### Context

The agent needs to understand the workspace without loading everything into its initial context window. The tension is between being informed (enough context to work correctly) and being lean (not wasting tokens on irrelevant detail).

### Alternatives considered

- **Everything in the prompt** — AGENTS.md, factory docs, all skills, vision docs, knowledge base entries. Rejected because initial context would be thousands of tokens of mostly irrelevant detail.
- **No navigation structure** — the agent discovers everything by reading directories. Rejected because the agent has no sense of where to start or what's important.
- **A single master doc** — one document that links to everything. This is close to what we ended up with, but AGENTS.md alone was insufficient (it didn't point to the "why" layer).

### Decision

The progressive disclosure chain:
1. **AGENTS.md** (~250 tokens) — entry point, points to factory-context.md
2. **docs/factory-context.md** (~3KB) — inventories all projects, their status, docs links, vision docs
3. **Discovery layer** — OpenWiki (what/how), vision docs/PRDs (why), skills (operations)
4. **Why layer** — knowledge base entries, session traces

Each layer is discovered on demand. The agent never loads everything — it follows pointers from the previous layer.

### Rationale

This keeps initial context lean (~2,500 tokens including the subagent tool description) while making the full depth of workspace knowledge accessible. The "why" layer is the deepest and most expensive to load, so it's the furthest downstream — only reached when design-intent questions arise.

### Consequences

- AGENTS.md must stay lean — pure navigation, no duplication
- Each layer must point clearly to the next
- Adding new documentation means adding a pointer, not increasing AGENTS.md

### Revision triggers

- The initial context footprint grows beyond ~3,000 tokens and needs pruning
- A new documentation layer is added that changes the chain's structure

---

## 4. Structured decision capture format

**Status**: accepted

### Context

The original `save-knowledge` skill captured generic freeform summaries of sessions. These flattened decisions into paragraphs, losing the structure that makes them useful months later — the reasoning, the rejected alternatives, the conditions that would invalidate the decision.

### Alternatives considered

- **Freeform prose** — the original approach. Simple to write but hard for agents to parse reliably.
- **Frontmatter-only** — machine-friendly but loses the narrative thread.
- **Markdown headings with structured fields** — chosen. Human-readable, machine-parsable, and each section is skimmable.

### Decision

Every decision entry uses this structure:

```
## Decision: <title>

**Status**: proposed | accepted | deprecated | superseded
**Date**: <yyyy-mm-dd>
**Session**: <path to session.jsonl>

### Context
### Problem
### Alternatives
### Decision
### Rationale
### Consequences
### Revision triggers
```

The **revision triggers** field is the most important — it tells a future agent when to stop trusting the entry. Without it, a decision lives forever even when the conditions that shaped it have changed.

### Rationale

Structured fields preserve the reasoning, not just the conclusion. The session link provides full depth when needed via the `extract-context` utility. Eight fields is enough to be useful without being burdensome to write.

### Consequences

- Entries are longer than a summary but more useful
- Agents can parse the structure programmatically
- The format is stable enough to build tooling around (search, cross-reference)

### Revision triggers

- The format proves too heavy for quick captures (if users stop using it, simplify)
- A search/retrieval need emerges that requires different fields

---

## 5. Session-grouped knowledge directory structure

**Status**: accepted

### Context

A single session can produce multiple design decisions. Under the original structure (`docs/knowledge/<topic>/<date>-<slug>/summary.md`), each save would go to a different topic directory, and re-running on the same session would overwrite rather than append. Multiple decisions from the same session had no natural grouping.

### Alternatives considered

- **Flat ADR-style** (`docs/adr/0001-slug.md`) — used by the opensource domain-modeling skill. Simple but doesn't group decisions by session, so session evidence (session.jsonl) has no natural home.
- **One directory per decision, session file duplicated** — works but wastes space and the grouping is implicit (same UUID in each copy).
- **One directory per session, decisions as sibling files** — the chosen approach.

### Decision

```
docs/knowledge/sessions/<session-uuid>/
  session.jsonl
  decisions/
    <sequence>-<slug>.md
```

Multiple decisions from the same session accumulate in the same session directory. Each decision file is independently linkable from the index. The session.jsonl is always the freshest snapshot (overwritten on each save).

### Rationale

Session grouping preserves the context in which decisions were made. The session.jsonl is the raw evidence; the decision files are the structured interpretation. Together they provide both depth (via session link) and readability (via structured fields). Grouping by UUID avoids naming collisions and makes the overwrite logic simple: check by UUID, always overwrite session.jsonl, append new decision files.

### Consequences

- Multiple sessions on the same topic produce separate UUID directories — no automatic grouping by topic
- The index must link to individual decision files, not session directories
- The session.jsonl is duplicated across saves (always overwritten with latest)

### Revision triggers

- Topic-based grouping becomes necessary for retrieval (add topic index or tags)
- The duplication of session.jsonl across sessions becomes a storage concern

---

## 6. Model-proactive decision capture

**Status**: accepted

### Context

If decision capture is purely manual, most decisions will never be recorded — the user won't remember to say "save this" in the middle of a design conversation. If it's fully autonomous, the agent records decisions the user doesn't consider significant.

### Alternatives considered

- **Manual only** — user says "save that." Simple but unreliable; most decisions would be lost.
- **Fully autonomous** — agent writes ADRs without asking. Risk of recording noise and missing the user's signal about what matters.
- **Workflow-integrated** — capture is part of the grilling process (product-layer sessions only). Good for structured product work but doesn't cover ad-hoc decisions in other contexts.

### Decision

The agent proactively identifies significant design decisions during conversation and suggests capturing them. The flow:

1. Agent recognises a decision meeting the criteria (hard to reverse, trade-offs involved, constrains future work)
2. Agent articulates *why* it's worth saving
3. User confirms or declines
4. If confirmed, agent calls save-knowledge to capture it

The save-knowledge skill's description signals proactivity: "*Use when preserving design intent or when a significant decision emerges that should be recorded.*"

### Rationale

This hits the sweet spot: the agent does the noticing and the framing, the user does the gatekeeping. The agent's suggestion is always accompanied by a reason, so the user can quickly judge whether the decision is worth recording. Over time, this builds a rich knowledge base without requiring the user to remember a separate save step.

### Consequences

- The agent must be able to recognise what a "significant decision" looks like
- Users may be interrupted by save suggestions — the agent should be judicious
- The pattern relies on the save-knowledge skill being accessible (via user invocation)

### Revision triggers

- The suggestion rate is too high (user ignores all suggestions) or too low (decisions consistently missed)
- A better capture trigger emerges (e.g. post-session summary that suggests entries)

---

## 7. Skills as packaging layer with disable-model-invocation

**Status**: accepted

### Context

The product-layer workflow and the decision-capture mechanism need to be available to the agent, but adding more descriptions to `<available_skills>` bloats the initial context. The user-called skills (product-layer, save-knowledge) don't need to be in the initial prompt — the user invokes them explicitly.

### Alternatives considered

- **Register all skills normally** — every skill appears in `<available_skills>`. Simple but wasteful; the product-layer skill doesn't need to be visible until called.
- **No skills** — embed workflow instructions in AGENTS.md or system prompt. Would mix concerns and make the prompt harder to maintain.
- **External docs only** — point to opensource skills from factory.txt without pi skill registration. Works but loses the ability to invoke via `/skill:name`.

### Decision

Skills that are user-called get `disable-model-invocation: true` in their frontmatter. This means:
- They are loaded and registered (invocable via `/skill:name`)
- They are **not** included in `<available_skills>` in the initial prompt
- The user types `/skill:product-layer` or `/skill:save-knowledge` to invoke them

Skills that the agent should discover on its own keep normal descriptions in `<available_skills>`.

### Rationale

This gives us the best of both: zero context cost for user-called skills, full discoverability for agent-discovered skills. The skill infrastructure (description, file path, base directory) is preserved for both types — only the prompt inclusion differs.

### Consequences

- User-called skills require the user to know the `/skill:name` command pattern
- Agent-discovered skills can be freely added without concern for context bloat
- The pattern is reusable for future user-called skills (e.g. assembly-layer invocation)

### Revision triggers

- The `/skill:name` pattern changes or is removed from pi
- A need emerges for user-called skills to also be agent-discoverable in some contexts