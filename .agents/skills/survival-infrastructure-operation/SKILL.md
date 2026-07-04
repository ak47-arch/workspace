---
name: survival-infrastructure-operation
description: Operate the survival-infrastructure personal intelligence system — a pipeline that captures raw narrative events, extracts structured data via LLM, stores markdown-native people/event nodes, and synthesizes wiki pages about people and topics. Use when the user wants to start/stop/rebuild the stack, check container status, tail logs, run the Flask app locally, or debug any part of the system.
---

# Survival Infrastructure Operation

Personal intelligence system: `survival-infrastructure/`.

```
INPUT CAPTURE (collection) → EXTRACTION (LLM parse + judge) → STORAGE (events/people) → WIKI SYNTHESIS (pages + topics)
                                                                     ↑
                                                            INSTRUCTIONS MODULE
                                                            (human-curated sources:
                                                             notes, URLs, citations, file uploads)
```

## Makefile — canonical interface

All operations go through the Makefile at the project root. No other scripts.

### Quick reference

| Command | What it does |
|---|---|
| `make` or `make start` | Ensure LLM is up, build & start app-dev container, verify HTTP |
| `make stop` | Stop all compose services |
| `make build` | Build app-dev image (without starting) |
| `make ps` | List running containers (LLM + survival) |
| `make logs` | Tail app-dev logs |
| `make shell` | Open a bash shell in the app-dev container |
| `make verify` | HTTP health-check app-dev endpoints |
| `make run` | Run Flask directly from venv (no container) |
| `make stop-run` | Stop the venv-run app |
| `make status-run` | Check if venv app is running |

### Variables (pass on command line)

| Variable | Default | Description |
|---|---|---|
| `TARGETS` | `app-dev` | One or more: `app-dev`, `app-prod`, `app-prod-copy`, `llm` |
| `CONTAINER_RUNTIME` | `podman` | `podman` or `docker` |
| `LLAMA_CPP_DIR` | `/home/anupam/llama-cpp/llama-b8763` | Path to llama.cpp build |

Examples:
```bash
make start                          # start app-dev (LLM auto-booted first)
make start TARGETS=prod             # start app-prod instead
make start TARGETS="dev prod"       # start app-dev and app-prod
make start TARGETS=llm              # start LLM only
make build TARGETS=prod             # build app-prod without starting
make logs TARGETS=prod              # tail app-prod logs
make shell TARGETS=dev              # shell into app-dev container
make verify TARGETS="dev prod"      # health-check both
```

### Execution order (`make start`)

1. `_ensure-shared-network` — create the compose network if absent
2. `_ensure-llm` — run preflight checks (LLAMA_CPP_DIR validity), start LLM container if not already running
3. `compose up -d --build $(TARGETS)` — build & start the app container(s)
4. `verify` — poll HTTP endpoints up to 18 attempts (~3 min) until all respond 200

## Environment

### .env file

The project `.env` file sets these defaults (all overridable):
```
CONTAINER_RUNTIME=podman
SURVIVAL_LLM_BASE_URL=http://llm-inference-server:8012
SURVIVAL_CONFIG_FILE=config/app.yaml
SURVIVAL_DATA_DIR=data
LLAMA_CPP_DIR=/home/anupam/llama-cpp/llama-b8763
```

### Config file

`config/app.yaml` controls:
```yaml
server:
  host: 127.0.0.1
  port: 5051
storage:
  data_dir: data
extraction:
  auto_start_worker: true
instructions:
  max_upload_bytes: 52428800    # ← config-driven upload limit (50 MB)
```

Overridable via env vars: `SURVIVAL_HOST`, `SURVIVAL_PORT`, `SURVIVAL_DEBUG`, `SURVIVAL_DATA_DIR`, `SURVIVAL_EXTRACTION_AUTO_START`, `SURVIVAL_INSTRUCTIONS_MAX_UPLOAD_BYTES`.

## Architecture

### Module/Service/Repository pattern

Every pipeline stage follows a clean 3-layer pattern:

```
module.py  ← HTTP boundary (Flask routes → response dicts with http_status)
service.py ← Business logic, validation, dedup
repository.py ← Persistence (JSONL, markdown files, file storage)
```

The Flask app (`app.py`) instantiates modules lazily via factory functions like `_instruction_module()`, `_collection_module()`, etc.

### Project layout

```
survival-infrastructure/
├── Makefile                    # ← canonical interface (use this)
├── app.py                      # Flask app with all routes
├── config/
│   ├── app.yaml                # Application config (server, storage, extraction, instructions)
│   └── workflows.yaml          # LLM workflow config
├── data/                       # Runtime data (gitignored)
│   ├── instructions/           # Instruction sources (JSONL + uploads)
│   ├── events/                 # Event markdown files + extraction JSON
│   ├── people/                 # Person markdown files
│   └── wiki/                   # Synthesized wiki pages
├── scripts/
│   └── verify_health.py        # HTTP health-check poller (called by `make verify`)
├── survival_infra/
│   ├── core/
│   │   └── config.py           # Config loading from YAML + env var overrides
│   └── pipeline/
│       ├── instructions/       # Instruction source ingest (notes, URLs, citations, files)
│       ├── event/
│       │   ├── collection/     # Raw capture ingest
│       │   ├── extraction/     # LLM parse + judge pipeline
│       │   ├── people/         # Person node CRUD
│       │   └── wiki/           # Wiki synthesis & governance
│       ├── analysis/           # (empty — future)
│       └── downstream/         # (empty — future)
└── docker-compose.yml
```

### Key API routes

| Method | Route | Module |
|---|---|---|
| POST | `/api/captures` | Collection — ingest a raw narrative |
| POST | `/api/extractions` | Collection — queue extraction for a capture |
| POST | `/api/parse` | Extraction — enqueue LLM parse job |
| POST | `/api/instructions/sources` | Instructions — upload a note/URL/citation/file |
| GET | `/api/instructions/sources` | Instructions — list sources |
| GET | `/api/people` | People — list person nodes |
| POST | `/api/people` | People — create person node |
| GET | `/api/wiki/people/<slug>` | Wiki — get synthesized person page |

### Instructions Module (detailed)

The instructions module (`pipeline/instructions/`) is a structured inbox for human-curated knowledge. It accepts four source types:

| Type | Content | Fingerprint |
|---|---|---|
| `freeform` | Plain text notes | SHA-256 of type + notes |
| `url_note` | URL + notes (URL canonicalized) | SHA-256 of type + canonical URL + notes |
| `citation_note` | Book/paper citation + notes | SHA-256 of type + citation + notes |
| `file_upload` | File bytes (documents only, 50 MB max) | SHA-256 of file bytes |

Deduplication is fingerprint-based — duplicate submissions return HTTP 409 with the existing `instruction_id`.

## Troubleshooting

### Container fails to start
```bash
make logs          # tail app logs
make ps            # check container state
make _ensure-llm   # ensure LLM is running (standalone)
```

### Port conflict
The compose file maps `5151:5051` for app-dev, `5152:5051` for app-prod, `5153:5051` for prod-copy. If any of these are taken:
```bash
sudo ss -tlnp | grep 5151  # find the offender
podman stop survival-app-dev && podman rm survival-app-dev  # clear old container
```

### LLM not responding
```bash
curl http://localhost:8012/health   # should return 200
curl http://localhost:8012/ready    # should return 200
make _ensure-llm                     # re-check + restart if needed
```

### Config changes not picked up
The config is baked into the Docker image at build time. After changing `config/app.yaml`:
```bash
make start    # rebuilds and redeploys automatically
```
Or for a faster iteration cycle on config-only changes, use `make run` (venv mode) which reads config from disk at each start.