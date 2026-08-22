## Decision: Complete session retention for Langfuse retrospective evals

**Status**: accepted
**Date**: 2026-08-19 04:55
**Task**: [multi-repo-delivery-bookkeeping-prs](../../../../tasks/multi-repo-delivery-bookkeeping-prs.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Retain the complete message-level session per run — everything Langfuse consumes (message_start/end with final content + usage, tool_execution_start/end with args + resul

### Context

Decision 05 diagnosed the evidence-pipeline bloat (`message_update → toolcall_delta` replay is O(n²)) and pointed at "message-level durable logs + compression". But the factory also needs session files that survive **wholesale** so runs can be reconstructed for **retrospective eval creation using Langfuse** — and a Langfuse stack is already hosted locally (`langfuse-web/worker/postgres/minio/redis/clickhouse`), aligned with the existing `[langfuse-agentic-operations]` backlog.

### Problem

"Message-level-only, compress hard" could be misread as *throw away trace detail*. But Langfuse evals need the **complete conversation-level trace** — messages, tool calls, tool results, model responses, usage/cost, timestamps, run provenance. The `message_update` delta-replay is emphatically NOT that: it is stream plumbing (per-keystroke argument-typing reconstruction) with zero eval value.

### Alternatives

- **Keep raw unfiltered** — rejected: the O(n²) replay makes retains grow to GB/2GB and blew GitHub's 100 MB evidence cap.
- **Summarize/truncate to a small sanitized doc-session** — rejected: loses what's needed to reconstruct and score a run retrospectively.
- **Keep complete message-level, compressed + versioned, with a Langfuse ingestion bridge** — chosen.

### Decision

Retain the **complete message-level session per run** — everything Langfuse consumes (`message_start/end` with final content + usage, `tool_execution_start/end` with args + results, `tool_execution_update` real output, turn and agent framing) — **minus only the `message_update` delta-replay**. Store it compressed and self-describing: manifest + provenance (repo, PR, verdict, model, timestamps) so any run can be reconstructed for retrospective scoring. Add a **Langfuse ingestion/export bridge** and a **retention tier policy** (history must survive for evals, so age/compression tiers, not bare deletion).

### Rationale
The delta-replay is inert plumbing; the message-level narrative is *both* the complete session and the eval-usable trace. Filtering the delta and compressing the rest satisfies the bloat fix (decision 05) and the retention requirement simultaneously — a run dir drops from GB-scale to lean, while the retained artifact remains complete for eval. This is the first half of the 05 pipeline (the durable-log filter is `bin/session-filter.sh`, PR #17); the ingestion bridge + retention follow.

### Consequences
- Run dirs no longer balloon O(n²); the durable session is lean but complete.
- Langfuse retrospective evals can reconstruct and score any saved run.
- Next: Langfuse ingestion bridge + retention tiers (follow-up task referencing `[langfuse-agentic-operations]`).

### Revision triggers
- If Langfuse evaluation ever needs token-by-token delta replay (it should not for message-level scoring).
- If a first-party pi/langfuse native ingestion path removes the need for the custom bridge.
