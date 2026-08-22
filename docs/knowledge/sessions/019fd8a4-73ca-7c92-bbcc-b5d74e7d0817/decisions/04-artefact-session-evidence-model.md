## Decision: One artefact per capture + the full pi session as evidence

**Status**: accepted
**Date**: 2026-08-08 21:43
**Task**: [extension-inline-agent](../../../../tasks/extension-inline-agent.md)
**Project**: feed_analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: One artefact, two files, linked

### Context

The user's goal is to capture posts *with more context*: the agent reasons
over the pending capture with the user, and what emerges is "curated user
data — an extension of their mind", to be saved and plugged into downstream
applications (and used as evidence for analysis / training / RL later). The
factory knowledge base stores raw agent conversations as pi-native
`session.jsonl` under `docs/knowledge/sessions/<uuid>/`, and can rebuild the
full context window from them (`docs/knowledge/bin/extract-context`).

### Problem

What exactly gets persisted when the user saves an agent-enriched capture?
How does the conversation (evidence) survive with it?

### Alternatives

- **Distilled answer only** (an `analysis` text field) — rejected: loses the
  reasoning, tool calls, and transcript the user explicitly wants to keep as
  evidence.
- **Embed the entire conversation inline in the tree line** — rejected:
  bloats the capture line and invents a bespoke format when pi already has a
  canonical one.
- **Two artefacts** (tree line + separate conversation line) — rejected: the
  user wants one artefact that carries the whole conversation.

### Decision

One artefact, two files, linked:

- `artefacts.jsonl` line = the capture tree (tweet_url, author, tweet_text,
  links, notes, children) plus an **`agent` envelope**: `{ sessionId,
  sessionFile, prompt, model, capturedAt }` pointing at the evidence.
- `sessions/<uuid>/session.jsonl` = the full pi conversation (prompt, tool
  calls, tool results, streaming text, thinking, usage/cost) written in pi's
  native session format — the same format the factory knowledge base stores
  and `extract-context` understands.

The session is the evidence; the tree line is the readable index entry.

### Rationale

Reuses pi's native session.jsonl format rather than inventing one, so
downstream apps (and factory tooling like extract-context) can consume the
evidence as-is. Keeps the capture line small and queryable while the full
conversation remains available verbatim.

### Consequences

- Capture saves gain an optional `agent` field; the server validates it.
- The agent service must persist each session and return a session id/file
  back to the panel so the envelope can reference it.
- The saved conversation is immutable evidence; no editing of answers (the
  user agreed — verbatim).

### Revision triggers

- If downstream apps need the conversation inline in the artefact line
  (single-file portability), reconsider embedding (cost: line size).
- If pi changes its session format, migrate evidence archives rather than
  changing the envelope contract.
