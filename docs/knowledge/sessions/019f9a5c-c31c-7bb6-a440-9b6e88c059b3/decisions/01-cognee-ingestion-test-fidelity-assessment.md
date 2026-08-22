## Decision: Cognee ingestion test — fidelity assessment

**Status**: accepted
**Date**: 2026-08-19 22:46
**Task**: [cognee-integration-evaluation](../../../../tasks/cognee-integration-evaluation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The test results show that cognee's current extraction + recall pipeline with deepseek/deepseek-v4-flash is not faithful enough to replace the file-based context engine.

### Context

The software factory's context engine is a progressive-disclosure pipeline (AGENTS.md → factory-context.md → discovery layer → knowledge base). A task was created to evaluate whether cognee (an open-source AI memory platform with knowledge graph + vector search) could serve as a backing store for this context engine — either as a replacement (standalone mode) or as an augmentation (switchable on/off).

A test-ingest was performed: 8 factory documents (factory-context.md, 2 vision docs, 5 decision records) were ingested into cognee via `remember()`, then 8 recall queries were run against the resulting graph. Backends: Ladybug (graph), LanceDB (vector), SQLite (relational). LLM: `deepseek/deepseek-v4-flash` via OpenRouter, embedding: `fastembed/BAAI/bge-small-en-v1.5` (local).

### Problem

Does cognee's extraction + recall pipeline produce faithful, context-preserving results from our factory documentation, or is the quality too low to be useful for the context engine?

### Alternatives

- **Skip testing and design integration architecture** — would commit to a design without empirical evidence.
- **Test with a different model** — plausible that extraction quality is model-dependent, but the agreed first step was to test with the current session model (deepseek v4 flash).

### Decision

The test results show that **cognee's current extraction + recall pipeline with `deepseek/deepseek-v4-flash` is not faithful enough** to replace the file-based context engine. Key findings:

1. **Lossy extraction**: 51 nodes / 68 edges from 8 substantial markdown documents is thin. The model failed to extract known entities and relationships.
2. **Hallucination**: Answers included facts not in source documents (e.g. "C2 capabilities" for survival-infrastructure, "SysAdmins handle infra" for merge policy, "pointer map as data structure").
3. **Missed context**: Queries about content explicitly in the ingested docs returned "context does not contain information" (e.g. capture instrument, progressive disclosure).
4. **Auto-router always defaulted to GRAPH_COMPLETION**: No vector/chunk search was exercised. The GRAPH_COMPLETION path relies entirely on the extracted graph, which was too thin.
5. **Cross-document relationships are weak**: The graph failed to capture known relationships between documents (e.g., the context-engine vs knowledge-base naming decision is explicitly documented but the graph didn't connect it).

### Rationale

The evaluation was empirical and bounded — 8 docs, 8 queries, default settings. The results are clear enough to conclude that the current pipeline is not viable for the context engine use case. However, the conclusion is conditional on the model used: DeepSeek v4 flash may not be suitable for instructor/litellm structured output extraction, which is what cognee's graph extraction depends on. The vector search pathway (CHUNKS query type) was not tested and could still be useful for semantic search over full text.

### Consequences

- **Design work for cognee integration is deferred** until/unless a model yields better extraction fidelity.
- **The augmentation mode (switchable on/off) is not yet evaluated** — the standalone mode failed first.
- **A retry with `gpt-4o-mini` or `gpt-4o`** could produce different results. The test script (`opensource/cognee/cognee_test_ingest.py`) is reusable with a different model.
- **The file-based context engine remains the primary approach** for now.
- **Vector search over chunked factory docs** (using cognee's CHUNKS search type) was not tested and could be a lower-risk augmentation path.

### Revision triggers

- A retry with a different model (gpt-4o-mini, gpt-4o, claude-sonnet) produces significantly better extraction quality.
- Cognee improves its extraction pipeline (e.g., LLM-free extraction via gliner2, seen in the `feature/cog-6188-gliner2-llm-free-extraction` branch).
- A need for semantic search over factory docs emerges that is not well served by grep/file-read.
