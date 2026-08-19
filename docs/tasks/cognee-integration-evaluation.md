# Task: cognee-integration-evaluation

**Status**: completed
**Category**: Small
**Project**: software-factory
**Created**: 2026-08-19 21:07
**Source**: docs/tasks.txt — `see how opensource/cognee can be intgrated into our ecosystem and what benefits it might provide and evaluate the benefits(software_factory)`

## Artifacts

- Cognee test script: `opensource/cognee/cognee_test_ingest.py`
- Graphify analysis: `opensource/graphify/` (v0.9.47, pulled from upstream)

## Sessions

- _(this session)_

## Decisions

- `01-cognee-ingestion-test-fidelity-assessment` — cognee extraction fidelity test results
- `02-graphify-mismatch-with-context-engine` — graphify does not fit the progressive disclosure architecture

## Evaluation Results

### Cognee (LLM-based knowledge graph)

**Date**: 2026-08-19 22:46
**Method**: Ingested 8 factory docs into cognee (default backends: Ladybug + LanceDB + SQLite) via OpenRouter `deepseek/deepseek-v4-flash`. Ran 8 recall queries against the resulting graph.

**Ingestion**: 8 files, 54.5s, 51 nodes / 68 edges — Thin extraction, lossy.

**Recall Quality**: 2/8 acceptable, 6/8 wrong, hallucinated, or missed — The extracted graph lost most semantic content and introduced hallucinated facts.

**Key Issues**:
1. Model matters — DeepSeek v4 flash is a poor extraction model for instructor/litellm structured output.
2. Auto-router always defaulted to GRAPH_COMPLETION — vector/chunk search never exercised.
3. Hallucination — answers included facts not in source docs (C2 capabilities, SysAdmins).
4. Cross-document relationships weak — graph failed to capture known connections.

**Verdict**: Not faithful enough to replace file-based context engine. Might improve with gpt-4o-mini or LLM-free extraction (gliner2 branch).

### Graphify (codebase intelligence graph)

**Date**: 2026-08-19 23:15
**Method**: Read ARCHITECTURE.md, README.md, BENCHMARKS.md, markdown extractor, extraction spec, skill-pi.md, and serve.py to understand the full pipeline.

**Architecture**: Two-tier pipeline:
- Tier 1 (deterministic): tree-sitter AST for code (37 languages), heading/link parsing for markdown.
- Tier 2 (LLM semantic pass): for docs/papers/images, the assistant's model (or Gemini) extracts entities + relationships via subagents.
- Query: keyword-matching + graph traversal (BFS/DFS from seed nodes). No vector embeddings.

**Why it doesn't fit**:
1. **Code-first design** — built for codebase understanding (call graphs, imports, class hierarchies). Our context engine is about factory documentation.
2. **Markdown extraction is structural only** — gives headings and links, not prose content. The LLM semantic pass is secondary and has the same fidelity issues as cognee.
3. **Query is graph traversal, not semantic search** — `graphify query` matches node labels and walks edges. Can't find content that wasn't extracted as graph nodes.
4. **No progressive disclosure** — dumps everything into one graph. No layered context (AGENTS.md → factory-context.md → discovery → file read).
5. **No full-text retrieval** — can't read or search raw document text, only the extracted graph.

**Verdict**: Graphify is excellent for codebase intelligence but does not fit the progressive disclosure architecture of the context engine.

## Overall Conclusion

**Neither cognee nor graphify, in their current form, are suitable replacements or augmentations for the factory context engine's progressive disclosure pipeline.**

- The **file-based system** (AGENTS.md → factory-context.md → discovery → file reads) remains the primary approach. It is zero-cost, zero-hallucination, and fully faithful.
- Cognee could be revisited if a better extraction model (gpt-4o-mini) or LLM-free extraction (gliner2) becomes available.
- Graphify would be valuable for a separate use case (codebase intelligence) but is orthogonal to the context engine problem.
- The augmentation mode (switchable on/off) was not viable without the standalone mode passing first.