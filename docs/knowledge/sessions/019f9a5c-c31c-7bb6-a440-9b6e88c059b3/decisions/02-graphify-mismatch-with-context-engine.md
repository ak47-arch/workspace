## Decision: Graphify does not fit the progressive disclosure context engine

**Status**: accepted
**Date**: 2026-08-19 23:20
**Task**: cognee-integration-evaluation
**Project**: software-factory
**Session**: sessions/019f9a5c-c31c-7bb6-a440-9b6e88c059b3/session.jsonl

### Context

After evaluating cognee as a potential backing store for the factory context engine, the task was extended to also evaluate graphify — another open-source knowledge graph project. Graphify was pulled from upstream (v0.9.44 → v0.9.47) and its architecture, pipeline, markdown extraction, semantic pass, and query mechanism were studied.

### Problem

Does graphify's structural + semantic extraction pipeline fit the factory context engine's progressive disclosure architecture (AGENTS.md → factory-context.md → discovery layer → file reads)?

### Alternatives

- **Assume graphify is a better cognee** — both are knowledge graphs, so graphify might solve the same problem with better fidelity.
- **Test graphify empirically** — run a test ingest similar to the cognee test and compare recall quality.

### Decision

Graphify does **not** fit the progressive disclosure architecture. The evaluation was architectural rather than empirical because the design mismatch is clear from the documentation alone:

1. **Code-first design**: Graphify is built for codebase intelligence (37 tree-sitter grammars, call graphs, import resolution, class hierarchies). The markdown/document support is secondary. Our context engine is about factory documentation, not code.

2. **Markdown extraction is structural, not semantic**: The markdown extractor produces page nodes, heading nodes, and `contains`/`references` edges. It does not extract prose content. The LLM semantic pass (for docs/papers/images) is a separate pipeline that has the same fidelity issues as cognee — it relies on the assistant's model (or Gemini) to extract entities from text, which is lossy and can hallucinate.

3. **Query is graph traversal, not semantic search**: `graphify query` matches query terms against node labels (trigram index) and walks the graph via BFS/DFS. It cannot find content that the LLM pass didn't extract as nodes. No vector search, no full-text retrieval, no semantic similarity.

4. **No progressive disclosure model**: Graphify dumps all content into one graph and queries it monolithically. There is no layered context system that progressively reveals more detail.

5. **No full-text retrieval**: The graph replaces file reading rather than augmenting it. The context engine needs to read raw document text faithfully.

### Rationale

The architectural analysis shows a fundamental mismatch between graphify's design (codebase intelligence, entity extraction, graph traversal) and the context engine's needs (faithful document retrieval, progressive disclosure, full-text search). An empirical test would confirm the same fidelity issues seen with cognee — the LLM semantic pass would lose content and hallucinate — without providing additional insight.

### Consequences

- **Graphify is not pursued further for the context engine**.
- **Graphify could be useful for a separate use case**: codebase intelligence for the factory's own code (e.g., mapping agent code, tool implementations, dependency graphs).
- **The file-based progressive disclosure system remains the primary approach** for the context engine.
- **Cognee could be revisited** if a better extraction model (gpt-4o-mini) or LLM-free extraction (gliner2 branch) becomes available, but the current evaluation is that it does not meet the fidelity bar.

### Revision triggers

- A need for codebase intelligence (understanding agent code structure, call graphs, dependencies) emerges — graphify would be the right tool for that.
- Graphify adds vector/embedding-based semantic search to its query pipeline.
- Graphify adds full-text document retrieval alongside graph traversal.
- A new tool emerges that combines faithful full-text retrieval with progressive disclosure and semantic search.