---
name: langfuse-tracing
description: Langfuse observability for pi agent traces — integration overview and recovery.
disable-model-invocation: true
---

# Langfuse Tracing

The pi extension at `.pi/extensions/langfuse-tracing.ts` pushes every agent turn (LLM calls + tool usage) to a self-hosted Langfuse instance at `opensource/langfuse/` (podman behind `DOCKER_HOST=unix:///run/user/1000/podman/podman.sock`). Credentials are in `.env.langfuse` and must match the `LANGFUSE_INIT_PROJECT_*` vars in `opensource/langfuse/.env`. If things go sideways, check container logs (`docker-compose logs langfuse-web`), verify the API responds at `http://localhost:3000/api/public/health`, and ensure the Basic auth header isn’t split by base64 line wrapping.

## Official skill (how to Langfuse)

For everything about using Langfuse — SDKs, CLI, prompt engineering, evals, error analysis, judge calibration — use the **official skill**:

`opensource/langfuse-skills/skills/langfuse/`

- `SKILL.md` — entry point: read it first.
- `references/` — topic guides: `cli.md`, `error-analysis.md`, `prompt-engineering.md`, `judge-calibration.md`, `v4-project-migration.md`, `trace-evaluator-upgrade.md`, `instrumentation.md`, `prompt-migration.md`, `user-feedback.md`, `ci-cd.md`, `skill-feedback.md`.
- Repo is upstream `langfuse/skills` — update via `git -C opensource/langfuse-skills pull --ff-only` (fast-forward only; never hand-edit shared docs).
- Company-specific facts live here in this wrapper; the official skill holds upstream knowledge.

## Operations (Level B)

Run from `opensource/langfuse/`. Podman: `export DOCKER_HOST=unix:///run/user/1000/podman/podman.sock` first (plain `docker` CLI is not installed).

| Task | Command |
|---|---|
| Start | `docker-compose up -d` |
| Stop | `docker-compose down` |
| Restart all | `docker-compose restart` |
| Restart app only | `docker-compose restart langfuse-web langfuse-worker` |
| Health | `curl -s http://localhost:3000/api/public/health` → expect `{"status":"OK","version":"4.x.y"}` |
| Logs (follow) | `docker-compose logs -f langfuse-web` (or `-f langfuse-worker`) |
| Versions | `podman ps --format '{{.Names}} {{.Image}} {{.Status}}'` (6 containers: postgres, redis, clickhouse, minio, langfuse-web, langfuse-worker) |

Health bar: `GET /api/public/health` returns 200/`status:OK`. **Healthy = web serves; worker may lag** — after an upgrade, give the worker a minute to run migrations and the event-propagation job before trusting dashboards. If the health endpoint is unreachable, the stack is down: start it, then check worker logs for migration failures. If migrations fail with a dirty `schema_migrations` state, see the upgrade decision record (`docs/knowledge/sessions/019fc40a-…/decisions/01-langfuse-v3-to-v4-upgrade.md`).

## v4 stack notes (since 2026-08)

- Stack runs Langfuse **v4** (`langfuse/langfuse:4`) with `LANGFUSE_MIGRATION_V4_WRITE_MODE=dual` set in `docker-compose.yml`. **Do not switch to `events_only`**: in that mode `/api/public/ingestion` rejects `trace-create`/`generation-create` events and pi tracing silently fails (only `score`/`log` events are accepted). `dual` keeps the v3 ingestion path working while enabling the v4 events architecture.
- Metrics/analytics dashboards in the v4 UI read from the new `events_core`/`events_full` tables populated by the worker’s event-propagation job (runs every minute). If a fresh ingest isn’t showing in events but the ingest returned 201, give the propagation job a minute and re-check.
- Legacy read endpoints (`GET /api/public/traces`, `GET /api/public/observations`) are **disabled in `events_only` mode**; use `GET /api/public/v2/observations?fromStartTime=…&toStartTime=…` instead.
- History: the 2026-08 v3→v4 upgrade required forcing ClickHouse golang-migrate past a dirty-version-1 state (`schema_migrations`, version 34 clean marker) to let migrations 0035–0046 run; 4200 observations were restored from `opensource/langfuse/.backups/clickhouse_observations.tsv` and 333 traces were reconstructed from observation inputs (see the migration decision record).