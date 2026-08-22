## Decision: Twitter knowledge base — plain files as truth, SQLite FTS5 derived index, thin read API

**Status**: accepted
**Date**: 2026-08-08 21:43
**Task**: [extension-inline-agent](../../../../tasks/extension-inline-agent.md)
**Project**: feed_analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Plain files as the canonical source of truth (artefacts.jsonl + Summary: ## Decision: Twitter knowledge base — plain files as truth, SQLite FTS5 derived index, thin read

### Context

Captures grow into a personal knowledge base over the user's Twitter
consumption — tweet content, urls, recursive comment nodes, plus the pi
artefacts and sessions. It must be **searchable and pluggable**: other
applications the user builds will consume it. The factory knowledge base
itself is plain files (curated index + decision markdown + raw session.jsonl)
searched with rg/grep — no database.

### Problem

How to store and expose the corpus: plain text files (like the factory KB) or
a search store?

### Alternatives

- **Plain files only** — pros: human/agent readable, diffable, portable, zero
  infra, matches factory paradigm, evidence is already files. Cons: `rg`
  search degrades past a few thousand captures, no relevance ranking, no
  structured querying, every downstream app re-implements parsing, no API.
- **Dedicated/vector store as canonical truth** — rejected: it would become
  the source of truth, losing file readability, and adds infra; vectors are
  overkill for keyword search today.

### Decision

**Plain files as the canonical source of truth** (artefacts.jsonl +
**Summary**: ## Decision: Twitter knowledge base — plain files as truth, SQLite FTS5 derived index, thin read API Status: accepted Date: 2026-08-08 21:43 Task: extension-inline-agent
sessions/) **plus a derived, rebuildable SQLite FTS5 index plus a thin read
API**:

- Files stay the durable, canonical store (mirrors the factory KB).
- A build step (`bin/rebuild-index`) loads the files into a `captures` SQLite
  table + FTS5 virtual table (BM25 ranking) at `capture/server/data/index.db`.
- The Python capture server exposes a read API (e.g. `GET/POST /search`)
  wrapping FTS5 `MATCH ... ORDER BY rank`, plus structured filters (author,
  date range), returning capture indexes + session pointers. Downstream apps
  query the API, not the files.

### Rationale

Keeps every plain-file pro (truth, portability, readability, evidence in
native format) and buys back the two cons that matter for a growing corpus —
search speed/relevance and a stable pluggable seam — with a throwaway,
rebuildable index rather than a canonical database.

### Consequences

- urls need a tokenizer strategy (default FTS5 tokenizer mangles urls); index
  urls in a way that preserves path components or as a separate column.
- The index is derived: safe to delete/rebuilt from files, never hand-edited.
- Evidence (session.jsonl) is not indexed directly — the artefact line is the
  index entry; sessions stay raw material.

### Revision triggers

- If captures grow to tens of thousands and FTS5 ranking no longer suffices,
  or semantic search is wanted, add embeddings/a vector layer on top of the
  same plain-file truth.
- If multi-writer concurrency or transactional updates become a requirement.
