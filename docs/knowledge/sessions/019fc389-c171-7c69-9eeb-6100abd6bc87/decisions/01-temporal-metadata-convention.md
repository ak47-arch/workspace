## Decision: Temporal Metadata Convention

**Status**: accepted
**Date**: 2026-08-02 18:00
**Task**: [chronological-tracking](../../../../tasks/chronological-tracking.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Every artifact carries a timestamp with minute precision (yyyy-mm-dd HH:MM).

### Context

The factory produces multiple artifact types — task files, knowledge base decision files, session files, PRDs — each with its own metadata. Previously, decision files had day-precision dates (`**Date**: 2026-07-30`) and task files had day-precision creation dates (`**Created**: 2026-07-30`). The knowledge base index was grouped by project but the order of entries within each section was ad-hoc. There was no way for an agent to reconstruct the chronological sequence of events without parsing UUIDs (v7) or cross-referencing git history.

### Problem

Agents needed to understand the order of events (which decisions came before which, how the factory evolved over time) but lacked a simple, queryable mechanism. A global sequence number was considered but rejected as too rigid — it requires a counter, breaks under concurrent creation, and creates a maintenance burden.

### Alternatives

1. **Global sequence numbers** — every artifact gets a sequential integer (T-0042, K-0015). Rejected: requires a shared counter, fails under concurrent out-of-band creation, zero-padding is fragile, and backfilling is error-prone.
2. **UUID v7 sorting** — extract timestamps from UUIDs. Rejected: opaque to agents, requires UUID parsing logic, not human-readable.
3. **Timestamp precision upgrade** (chosen) — bump `**Date**` / `**Created**` from day to minute precision (`yyyy-mm-dd HH:MM`). Agents use `rg` + `sort` for chronological order. No coordination, no counters.

### Decision

Every artifact carries a timestamp with **minute precision** (`yyyy-mm-dd HH:MM`). Specifically:

- **Decision files**: `**Date**: <yyyy-mm-dd HH:MM>` — the time the decision was captured
- **Task files**: `**Created**: <yyyy-mm-dd HH:MM>` — when the task file was created
- **Knowledge base index**: entries sorted **oldest → newest** within each project section
- **PRDs**: `**Date**: <yyyy-mm-dd HH:MM>` (optional, since filename already carries the date)

The convention is documented in `docs/factory-context.md` under `## Temporal Metadata` so agents discover it before searching.

### Rationale

- Zero coordination — each tool stamps its own timestamp at creation time
- Trivial query — `rg "^\*\*(Date|Created)\*\*" | sort` gives a definitive timeline
- Human-readable — the timestamp is in the file, not encoded in a UUID or sequence number
- Backward compatible — existing entries can be backfilled with git commit timestamps
- No global state — no counters, no registries, no namespace collisions

### Consequences

- The save-knowledge skill template updates `**Date**: <yyyy-mm-dd>` → `<yyyy-mm-dd HH:MM>`
- The product-layer skill task file template updates `**Created**: <yyyy-mm-dd>` → `<yyyy-mm-dd HH:MM>`
- `bin/transition-task.sh` uses `date +%Y-%m-%d\ %H:%M` instead of `date +%Y-%m-%d` for completion dates
- Existing entries (~30+ decision files, ~5 task files) need backfilling via git commit timestamps
- The knowledge base index needs re-sorting oldest→newest within each project section

### Revision triggers

- If minute precision proves insufficient for ordering (e.g., multiple decisions in the same minute from concurrent sessions), bump to seconds (`HH:MM:SS`) — the format is the same, just longer
- If the workspace grows to multiple concurrent agents, the creation-time timestamp approach still works (no coordination needed), but the backfill strategy may need revisiting for entries created outside git
