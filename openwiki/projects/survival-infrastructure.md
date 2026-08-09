---
type: Project
title: Survival Infrastructure
description: Personal intelligence pipeline — captures freeform event narratives, extracts structured data via LLM, stores people/event nodes, and synthesizes wiki pages.
tags: [pipeline, flask, llm, wiki, extraction]
resource: /survival-infrastructure
---

# Survival Infrastructure

A staged data-pipeline application for capturing real-world events and processing them over time. The pipeline model is:

```
collection → extraction → analysis → downstream
```

## Architecture

The system is designed around **capture-first** principles:

1. **Collection must be durable and fast** — users save event narratives immediately
2. **Extraction must be asynchronous** — LLM inference runs independently after capture
3. **Each pipeline stage is independently evolvable**
4. **All persisted data lives under a configurable data root**
5. **Runtime behavior is controlled by external config**

```
┌─────────────────────────────────────────────────────────┐
│  app.py (Flask :5051)                                    │
│                                                          │
│  Routes:                                                  │
│    /api/captures          → Collection stage              │
│    /api/extractions       → Extraction stage (LLM)        │
│    /api/instructions      → Instruction sources module    │
│    /api/wiki              → Wiki synthesis & governance   │
│    /api/events            → Legacy event endpoints         │
│    /instructions          → Jinja2 UI panels              │
│                                                          │
│  LLM via: llm_client.WorkflowClient(config/workflows.yaml)│
└──────────────────────────┬───────────────────────────────┘
                           │ HTTP
                           ▼
              [llm/ Inference Server] (/openwiki/projects/llm-server-client.md)
```

## Pipeline Stages

### Collection Stage

- `POST /api/captures` — Store freeform event text + date/time immediately
- `GET /api/captures` — Recent raw captures for UI listing
- Saved to `<data_dir>/raw_captures.jsonl` (append-only log)

### Extraction Stage

- `POST /api/extractions` — Enqueue extraction for a `raw_id`
- `GET /api/extractions/<raw_id>/status` — Job pickup + live status
- `POST /api/extractions/<raw_id>/curation` — Actor-to-person mapping
- Successful extraction writes immutable event JSON: `<data_dir>/events/ev_<raw_id>.json`
- Narrator self-references (`I`, `me`, `my`) are auto-filtered from actor names
- Narrator-only actor output auto-resolves curation

### Wiki / Intel Stage

- `POST /api/wiki/people/<slug>/ingest` — LLM synthesis of a person wiki page from resolved events
- `GET /api/wiki/people/<slug>` — Return synthesized wiki page markdown
- `POST /api/wiki/topics` — Cross-person topic synthesis from a list of people slugs
- `GET /api/wiki/search?q=<query>&mode=lexical|hybrid&type=all|people|topics`
- Wiki pages include governance metadata: confidence score, last synthesized timestamp, archive markers
- All synthesis passes a 5-check lint gate before persistence

### Instruction Sources Stage

- `POST /api/instructions/sources` — Ingest instruction sources (`freeform`, `url_note`, `citation_note`, `file_upload`) with deterministic duplicate detection
- `GET /api/instructions/sources` — List captured instruction sources
- Module-boundary issues tracked with persistent IDs (`ISS-001`, `ISS-002`, ...)

## Configuration

**`config/app.yaml`:**

```yaml
server:
  host: 127.0.0.1
  port: 5051
  debug: false
storage:
  data_dir: data
extraction:
  auto_start_worker: true
instructions:
  max_upload_bytes: 52428800
```

**`config/workflows.yaml`** — LLM workflow definitions consumed by `llm_client.WorkflowClient`. Defines model references, system prompts, temperature, and fallback functions for extraction, classification, and synthesis workflows.

### Environment Variable Overrides

| Env Var | Overrides |
|---------|-----------|
| `SURVIVAL_CONFIG_FILE` | Config file path |
| `SURVIVAL_DATA_DIR` | `storage.data_dir` |
| `SURVIVAL_HOST` | `server.host` |
| `SURVIVAL_PORT` | `server.port` |
| `SURVIVAL_LLM_BASE_URL` | LLM endpoint base URL |
| `EXTRACTION_JUDGE_MODE` | `always` / `on_risk` / `never` |

## Data Storage Model

All artifacts under configured `data_dir`:

| Path | Contents |
|------|----------|
| `raw_captures.jsonl` | Append-only raw capture log |
| `events/ev_<id>.json` | Immutable structured event files |
| `people/<slug>.md` | Person markdown files |
| `people/photos/` | Person photos |
| `jobs/` | Async extraction job state |
| `runtime/app.jsonl` | Structured runtime events |
| `runtime/access.jsonl` | HTTP access logs |
| `runtime/audit.jsonl` | State-transition audit logs |
| `wiki/people/<slug>.md` | Synthesized person wiki pages |
| `wiki/topics/<slug>.md` | Synthesized topic pages |
| `wiki/index.md` | Wiki catalog |
| `wiki/log.md` | Append-only wiki mutation log |

## Operations

The canonical interface is the `Makefile`. Key commands:

| Command | Action |
|---------|--------|
| `make` / `make start` | Ensure LLM up, build & start app-dev container |
| `make stop` | Stop all compose services |
| `make build` | Build app-dev image |
| `make ps` | List running containers |
| `make logs` | Tail app-dev logs |
| `make shell` | Bash in app-dev container |
| `make verify` | HTTP health-check |
| `make run` | Run Flask directly from venv (no container) |

See [survival-infrastructure-operation skill](/.agents/skills/survival-infrastructure-operation/SKILL.md) for agent-oriented ops instructions.

## Known Issues

- **`start_stack.sh` broken** — Calls missing `compose_env_preflight.sh` that was deleted during llm_client migration. Workaround: use `docker-compose up -d` directly. Tracked as Issue 3 in [KNOWN_ISSUES.md](/docs/KNOWN_ISSUES.md).
- **Data quality** — Comprehensive [DATA_STRUCTURES_REPORT.md](/survival-infrastructure/DATA_STRUCTURES_REPORT.md) catalogs 5 pipeline tiers with structural weaknesses and 6 prioritized improvements.

## Source Files

| File | Purpose |
|------|---------|
| `/survival-infrastructure/app.py` | Flask application with all routes |
| `/survival-infrastructure/config/app.yaml` | Application configuration |
| `/survival-infrastructure/config/workflows.yaml` | LLM workflow configuration |
| `/survival-infrastructure/survival_infra/pipeline/collection/` | Raw capture ingest |
| `/survival-infrastructure/survival_infra/pipeline/extraction/` | LLM parse + judge pipeline |
| `/survival-infrastructure/survival_infra/pipeline/people/` | Person node CRUD |
| `/survival-infrastructure/survival_infra/pipeline/wiki/` | Wiki synthesis & governance |
| `/survival-infrastructure/survival_infra/pipeline/instructions/` | Instruction source ingest |
| `/survival-infrastructure/survival_infra/core/config.py` | Config loading from YAML + env vars |
| `/survival-infrastructure/tests/` | pytest suite |
| `/survival-infrastructure/Makefile` | Canonical operations interface |
| `/survival-infrastructure/scripts/verify_health.py` | HTTP health-check poller |
