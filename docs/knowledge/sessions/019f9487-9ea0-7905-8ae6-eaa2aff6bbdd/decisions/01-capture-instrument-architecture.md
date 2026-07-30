## Decision: Capture instrument architecture (thin extension + dumb server + decoupled backend)

**Status**: accepted
**Date**: 2026-07-25
**Project**: feed-analyser
**Session**: sessions/019f9487-9ea0-7905-8ae6-eaa2aff6bbdd/session.jsonl

### Context

The feed_analyser application (6,000+ lines, 5 containers, 13 specs) was built as a monolithic system: ingest → classify → scout → dashboard. Only the Twitter ingestion step was actually used. The rest was speculative bloat. The user wanted to pivot from "collect and analyse later" to "capture in context while browsing."

### Problem

The old model had three fatal flaws:
1. Batch collection produced low-signal data without semantic context.
2. X/Twitter auth restrictions prevented retrospective analysis of collected tweets.
3. Most features existed speculatively and were never validated against real use.

A new architecture was needed that cleanly separates capture from processing, so each can evolve independently without dragging the other along.

### Alternatives

1. **Build a full web app (monolithic, like before)** — rejected. Proven to fail for this user. Too much scope, too many unused features.
2. **Extension-only, no backend** — rejected. Browser storage is limited and LLM analysis can't run in an extension (Manifest V3 service worker limits).
3. **Extension that talks directly to a vector DB** — rejected. Premature to pick the storage tech before understanding the data patterns.
4. **Chosen**: Thin extension (captures only) → local dumb server (writes JSONL) → decoupled backend apps (built later).

### Decision

Three-tier architecture:
- **Extension** (thin): Chrome MV3 extension, manual capture only. Scrapes tweet text, links, visible comments from the DOM. Opens a side panel for review, text selection, and notes. POSTs the artefact to the local server. Does nothing else.
- **Server** (dumb): Local FastAPI, single POST endpoint. Validates the artefact shape, appends to `artefacts.jsonl`, returns 200. No enrichment, no dedup, no LLM calls, no analysis.
- **Backend apps** (future, decoupled): Read from the JSONL file (and optionally from the legacy SQLite DB). Do whatever analysis, workflow, or execution is needed. Completely independent of the extension.

Data is read-only after capture. Artefacts are immutable.

### Rationale

The separation of concerns is the key insight: capture and processing have different lifecycle needs. The extension should be small enough to maintain easily (X's DOM changes frequently). The server is a dumb pipe — it doesn't need to understand the data, just store it. Backend apps can be built, changed, or discarded without affecting how data is collected.

JSONL as the interim format avoids premature commitment to a storage technology (vector DB, PostgreSQL, etc.) until the data patterns and query needs are well understood.

### Consequences

- Extension is easy to rebuild when X breaks something — it has minimal logic.
- Server has zero business logic — it's a file writer.
- Data is available in a simple, portable format (JSONL) — any tool can read it.
- Backend apps can be added incrementally without touching the capture pipeline.
- The legacy feed_analyser data (SQLite) and new capture data (JSONL) coexist — future apps can read both.

### Revision triggers

- If the JSONL file grows large enough that reading/querying becomes slow (e.g., >100K lines), storage migration becomes urgent.
- If the user needs to capture from other platforms (YouTube, Gmail, GDrive), the extension may need to be extended or separate extensions built for each platform.
- If Manifest V3 restrictions become a blocker (e.g., service worker timeouts during side panel interaction), revisit extension architecture.