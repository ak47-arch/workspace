## Decision: Artefact data model and JSONL storage

**Status**: accepted
**Date**: 2026-07-25 20:01
**Project**: feed-analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Artefact shape (sent from extension to server)

### Context

When a user captures a tweet, the extension needs to send data to the server. The shape of that data, where it's stored, and how the server handles it are foundational to the entire system.

### Problem

The old system stored data in SQLite with a rigid schema (ideas table with category, intent, TLDR, etc.) that required upfront classification. The new system must be schema-light because downstream apps haven't been designed yet. The storage format must be portable and not commit to a specific query engine.

### Alternatives

1. **SQLite (old schema)** — rejected. The rigid schema (category, intent, tldr fields) doesn't fit the artefact model. SQL without vector extensions doesn't support semantic retrieval.
2. **PostgreSQL + pgvector** — rejected. Premature infrastructure for a personal tool. The data patterns aren't understood yet.
3. **ChromaDB / vector DB** — rejected. Same as above — premature commitment.
4. **JSONL (JSON Lines)** — chosen. Append-only, line-delimited JSON. Every line is a complete artefact. Simple to read, write, and transform. Any tool or language can process it.
5. **Artifact with notes field** — chosen based on user suggestion. Adds semantic richness from the user's own context at capture time.

### Decision

**Artefact shape** (sent from extension to server):

```json
{
  "tweet_url": "https://x.com/user/status/123",
  "author": "@user",
  "tweet_text": "full tweet text auto-scraped",
  "links": ["https://github.com/..."],
  "selected_texts": ["user highlights", "relevant comments"],
  "notes": "free text user context",
  "captured_at": "2026-08-03T14:30:00Z"
}
```

**Storage**: JSONL file (`artefacts.jsonl`), one line per capture. Server appends, never modifies existing lines.

**Server behaviour**:
- Validates that `tweet_url`, `captured_at` are present.
- Appends the artefact as a JSON line to `artefacts.jsonl`.
- Returns 200 on success, 400 on invalid input.
- No dedup — same tweet captured twice = two independent artefacts.

**Error handling**:
**Summary**: ## Decision: Artefact data model and JSONL storage Status: accepted Date: 2026-07-25 20:01 Project: feed-analyser Session: session.jsonl
- Server offline: error displayed in side panel, data stays in panel, user retries.
- Auto-scrape failure: yellow warning shown, Save still active. Tweet URL is always the anchor.

### Rationale

JSONL is the simplest durable format that works. Append-only means no data corruption risk from concurrent writes. Line-delimited means you can tail, grep, and process with standard Unix tools. No schema enforcement beyond what the server validates — downstream apps interpret the data however they want.

The notes field captures the user's own interpretation at the moment of capture, when context is freshest. This is signal that can't be recovered later.

### Consequences

- No built-in dedup — downstream apps must handle it if needed.
- No indexing — querying means scanning the file. Fine for thousands of lines, problematic for hundreds of thousands.
- Porting to a proper database later is straightforward: read JSONL line by line and insert.
- The server has zero business logic — it's effectively a file writer with validation.

### Revision triggers

- If `artefacts.jsonl` exceeds a size where reading it becomes slow (e.g., >100K lines), port to a proper storage system.
- If the artefact shape proves insufficient for downstream apps (e.g., missing fields that are expensive to reconstruct).
- If multiple backend apps need concurrent write access to the same JSONL file.
