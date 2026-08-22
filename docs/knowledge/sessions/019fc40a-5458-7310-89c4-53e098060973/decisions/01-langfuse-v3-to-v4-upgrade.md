## Decision: Self-hosted Langfuse v3 → v4 Upgrade with Data Recovery

**Status**: accepted
**Date**: 2026-08-09 22:40
**Task**: [langfuse-agentic-operations](../../../../tasks/langfuse-agentic-operations.md)
**Project**: langfuse-agentic-operations
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Proceed with repair

### Context

The self-hosted Langfuse stack (`opensource/langfuse/`, podman, 6 containers) ran v3.221.1 since before the `langfuse-agentic-operations` task began. The user asked to "get the latest code running". v3 data: 1 user, 1 project (`pi-agent`), 327 traces, 4,200 observations in ClickHouse, plus schema_migrations cleanly at version 37.

### Problem

A straight `git checkout v4.5.0` + `docker-compose up` failed: the v4 ClickHouse migration runner reset the golang-migrate `schema_migrations` tracker to `(1, dirty=1)` and refused to continue ("Dirty database version 1. Fix and force version."). Worse, the v4 migration chain *drops and recreates* data tables — ClickHouse `observations` went 4,200 → 2 rows, `traces` → 0, `scores` → 0. The stack was down for ~31h awaiting a decision.

### Alternatives

1. **Roll back to v3** (v3 images + `.env.v3.bak` existed). Zero risk, but defers the upgrade and leaves the platform on a deprecated version.
2. **Repair the v4 migration** (chosen). Required forcing the tracker and restoring data from backups.
3. **Fresh v4 install** — would have lost all data permanently.

### Decision

Proceed with repair:

1. **Migration repair**: inspected evidence that v4 migrations 0001–0034 had actually *applied* (tables had v4 schema markers: `event_ts`/`is_deleted` on traces/observations, `long_string_value` on scores) despite the broken tracker. Inserted a clean `(34, dirty=0)` marker into `default.schema_migrations` and deleted the stale `(1, dirty=1)` row, letting golang-migrate resume at 0035 and apply through 0046 (which drops `event_log`, `project_environments`, `dataset_run_items` and creates the v4 events architecture: `events_core`, `events_core_mv`, `events_full`, `observations_batch_staging`).
2. **Data restore**: re-imported 4,208 observations from the pre-upgrade backup `opensource/langfuse/.backups/clickhouse_observations.tsv` (477MB TSV, columns matched v4 schema exactly). The `traces` parent table was **not in the backup**, so 333 trace rows were reconstructed from observation inputs: Python-parsed the root GENERATION's input JSON (OpenAI content-array format), extracted the last user message as the trace name, and inserted with schema-aligned TSV. `scores` raw table was never backed up (only the hourly aggregate `analytics_scores`, which is a v4 View) — the one manual demo score (`task-completion`) was accepted as lost; score configs live in Postgres (intact).
3. **Write mode**: set `LANGFUSE_MIGRATION_V4_WRITE_MODE=dual` in `docker-compose.yml` and `.env` (compose anchor `&langfuse-worker-env`). v4 defaults to `events_only`, which **rejects `trace-create`/`generation-create` ingestion events** — would silently break the pi tracing extension. `dual` keeps the v3 ingestion path working while enabling the v4 events architecture.
4. **Cleanup**: removed v3 langfuse images (2.48 GB). Kept `clickhouse-server:latest` (unreferenced but small).

### Rationale

Repair over rollback because: the migration was 90% applied (only 0035–0046 pending), a full rollback would discard working v4 progress and postpone the inevitable, and data was recoverable (observations backed up; traces reconstructible from observations; Postgres – the source of truth for projects/API keys/score configs – was never at risk). `dual` over `events_only` because pi's extension is the primary ingest path and silent breakage (the stack had been silently down for 3 days before) is the failure mode this task exists to prevent. Reconstructing rather than losing the traces keeps the teaching dataset (323+ real traces) usable for the eval lessons.

### Consequences

- Stack now runs **Langfuse 4.6.0** (`docker.io/langfuse/langfuse:4`), healthy, all 46 migrations applied.
- Live pi tracing verified end-to-end: the current session's turns appear as traces in real time.
- v4 events tables populate via the worker's event-propagation job (~1/min); legacy read endpoints (`/api/public/traces`) still work in `dual` mode; v2 observations endpoint available.
- The `.backups/` directory (477MB observations TSV + postgres.dump + reconstruction scripts `trace_inputs.tsv`/`traces_import.tsv`) is now stale-but-safe to keep; a fresh backup post-migration is recommended.
- `.agents/skills/langfuse-tracing/SKILL.md` updated with the v4/dual-mode operational notes (never switch to `events_only`).

### Revision triggers

- Upstream Langfuse deprecates `LANGFUSE_MIGRATION_V4_WRITE_MODE=legacy`/`dual` (then pi's extension must move to the v2 events ingestion API).
- The golang-migrate tracker breaks again on a future upgrade (v4→v5) — the dirty-version repair may not recur if the upgrade path is cleaner.
- If the reconstructed trace names (parsed from observation inputs, up to 90 chars) are ever found inaccurate, re-run the reconstruction from the backup artifacts.
