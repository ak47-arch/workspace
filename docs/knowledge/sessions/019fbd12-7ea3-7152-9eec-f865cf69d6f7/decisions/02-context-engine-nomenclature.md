## Decision: Rename knowledge_base Factory Component to context_engine

**Status**: accepted
**Date**: 2026-08-02 15:09
**Task**: [combine-factory-context-factory-txt](../../../../tasks/combine-factory-context-factory-txt.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Rename the factory component from knowledge_base to context_engine in docs/factory-context.md.

### Context

The factory component called `knowledge_base` shared its name with the `docs/knowledge/` data directory. This created a contradiction in the factory model description: the component was described as "infrastructure spine — every other component reads/writes it" (always-on, foundational), while the same paragraph ended with "the knowledge base is the last stop — consulted only when code, docs, and vision don't answer the question" (last-resort, rarely used). These are two different things with the same name.

### Problem

The nomenclature collision made the factory model self-contradictory. An agent reading the description would be confused about whether the knowledge base is foundational (always used) or a last resort (rarely used). The same word meant two different things:
1. The factory component that provisions context to all other components
2. The curated decision records in `docs/knowledge/` — one data source within that component

### Alternatives

- **Rename the data directory** (`docs/knowledge/` → `docs/decisions/`). Rejected because "Knowledge Base" is well-established in AGENTS.md, the disclosure chain diagram, and `docs/knowledge/index.md`. Changing it would require updating many references and the name is appropriate for what it contains.

- **Use qualifiers everywhere** ("knowledge base component" vs "knowledge base data"). Rejected because it's verbose, error-prone, and the contradiction would still be in the paragraph.

- **Rename the factory component**. Chosen.

### Decision

Rename the factory component from `knowledge_base` to `context_engine` in `docs/factory-context.md`. The data directory stays `docs/knowledge/`.

The context engine is the infrastructure spine — it provisions context to all other components via progressive disclosure. The knowledge base (`docs/knowledge/`) is one layer within the context engine: the deepest, most expensive layer, deliberately the last resort.

### Rationale

- Eliminates the contradiction: "context engine is the spine" and "knowledge base is the last resort" are now two different sentences about two different things.
- The context engine describes the *system* (the progressive disclosure chain, all its layers, the tooling). The knowledge base describes the *data* (curated decisions, session traces).
- No breakage: AGENTS.md, the disclosure chain diagram, and `docs/knowledge/index.md` all stay unchanged because "Knowledge Base (Last Resort)" refers to the data, not the component.

### Consequences

- `docs/factory-context.md` updated: `knowledge_base` → `context_engine` in the 4-component model.
- The paragraph now reads: "**context_engine** — Infrastructure spine. Every other component reads/writes it. ... The knowledge base (`docs/knowledge/` — curated design decisions) is the last stop."
- Historical decision records that reference `knowledge_base` as a component name are preserved as-is.
- No other files need updating.

### Revision triggers

- If the factory component model is restructured (add/remove/rename components).
- If a better name for the component emerges that is more descriptive than "context_engine."
