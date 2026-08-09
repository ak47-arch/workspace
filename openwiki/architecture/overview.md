---
type: Architecture
title: System Architecture Overview
description: Cross-project architecture, data flow, dependency map, and shared infrastructure for the workspace ecosystem.
tags: [architecture, infrastructure, llm, containers]
resource: /
---

# System Architecture Overview

## Architectural Model

The workspace follows a **centralized inference hub with multiple downstream consumers** pattern:

```
                        ┌─────────────────────┐
                        │   headroom-pi        │
                        │   (compression       │
                        │    proxy on :8787)   │
                        └────────┬────────────┘
                                 │ routes through
                                 ▼
┌─────────────────────────────────────────────────────┐
│              LLM Inference Server (llm/)             │
│              Flask app on :8012                      │
│              ┌──────────────────────────────────┐   │
│              │  Router → Provider (gemma_e2b,   │   │
│              │           OpenAI-compatible,      │   │
│              │           llama.cpp subprocess)   │   │
│              └──────────────────────────────────┘   │
│  Services: /v1/chat/completions, /metrics, /health  │
└────────────┬────────────────────────────────┬───────┘
             │ HTTP inference                  │ HTTP inference
             ▼                                ▼
┌────────────────────────┐   ┌──────────────────────────┐
│ survival-infrastructure│   │    feed_analyser          │
│ (Flask :5051)          │   │    (FastAPI :8000)        │
│                        │   │                           │
│ Pipeline: capture →    │   │ Pipeline: ingest →        │
│ extract → people/wiki  │   │ classify → scout          │
│ Via: llm_client        │   │ Via: llm_client           │
│ workflows.yaml         │   │ workflows.yaml            │
└────────────────────────┘   └──────────────────────────┘

┌──────────────────────────────────────────────────────┐
│ workspace-portability                                 │
│   Phase 1: magic-setup → bootstrap-orchestrator       │
│   Phase 2: setup-guide → secrets, assets, services    │
│   Backup: create-all-snapshots → GDrive + GitHub      │
└──────────────────────────────────────────────────────┘
```

## Shared Infrastructure

### Container Runtime

- **Podman** is the default runtime across all projects.
- **Docker** remains a supported fallback (set `CONTAINER_RUNTIME=docker`).
- A shared external network `workspace-shared-llm-network` connects containers across projects.

### LLM Client Package

The `llm-client` pip package (source in `/llm/llm_client/`) provides a uniform `WorkflowClient` that both downstream apps consume:

- [survival-infrastructure](/openwiki/projects/survival-infrastructure.md) uses it for extraction, wiki synthesis, and event parsing
- [feed_analyser](/openwiki/projects/feed-analyser.md) uses it for tweet classification and scouting

Both apps own a per-project `config/workflows.yaml` that defines model references, system prompts, temperature, and fallback functions. The client code is identical across projects.

**Known issue:** The `llm_client` package is currently served via PYTHONPATH volume mount rather than being baked into container images. See [KNOWN_ISSUES.md](/docs/KNOWN_ISSUES.md).

### Data Flow

```
[User captures events] → survival-infrastructure POST /api/captures
    ↓ raw_captures.jsonl
[Extraction job enqueued] → POST /api/extractions
    ↓ LLM inference via llm_client → llm/ server
[Structured events] → events/ev_<id>.json
    ↓
[People / Wiki synthesis] → post LLM inference
    ↓
[Markdown wiki pages] → data/wiki/people/, data/wiki/topics/
```

```
[Twitter feed] → browser console scraper / headless scraper
    ↓ raw JSON → backend/raw_data/
[Ingestion pipeline] → API sync → SQLite classification
    ↓ LLM inference via llm_client → llm/ server
[Classified + scored posts] → database → UI dashboard
```

### Agent Skills

The workspace defines agent skills under [/.agents/skills/](/openwiki/reference/agent-config.md):

- **ssh-themistocles** — SSH connection to a secondary Debian machine with tmux-based resilience
- **survival-infrastructure-operation** — Full Makefile-driven ops for the pipeline app
- **product-layer** — Operates the software factory's [product/architecture layer](/openwiki/projects/software-factory.md): grills requirements, produces plan documents, tracks tasks
- **save-knowledge** — Captures design decisions into the session-based knowledge base

### Software Factory

The workspace is developed under a **software factory** paradigm (see `docs/factory-context.md` and the [Software Factory](/openwiki/projects/software-factory.md) page): a `context_engine` infrastructure spine with progressive disclosure, a `product/architecture` UX layer, a `project_management` lifecycle, and an `assembly_line` (CI/CD, agents, testing). The lifecycle tooling lives in `/bin/` (`transition-task.sh` + its test suite).

## Cross-Project Dependency Map

| Project | Depends On | Consumed By |
|---------|-----------|-------------|
| llm/ | llama.cpp binary, GGUF model files | survival-infrastructure, feed_analyser, pi (via headroom) |
| llm_client | llm/ server at runtime | survival-infrastructure, feed_analyser (legacy), pi (via headroom) |
| headroom-pi | headroom OSS binary | pi coding agent |
| workspace-portability | GitHub Release storage, GDrive | All projects (backup/restore) |
| survival-infrastructure | llm/ (via llm_client) | None (end-user app) |
| feed_analyser/capture | none (local-first JSONL) | downstream analysis apps (phase 2) |

## Key Differences from Monorepo

This is **not** a monorepo. Each sub-project is an independent git repository with its own CI, tests, and deploy strategy. The root repository acts as a workspace coordinator that tracks them all (through git submodules, plain directories, or workspace-portability's repo sync). The shared network `workspace-shared-llm-network` is the only runtime coupling between projects.

## Source File Map

| Area | Key Files |
|------|-----------|
| LLM Server | `/llm/service_app.py`, `/llm/router.py`, `/llm/local_server_runtime.py` |
| LLM Client | `/llm/llm_client/workflow_client.py`, `/llm/llm_client/config.py` |
| Survival Infra | `/survival-infrastructure/app.py`, `/survival-infrastructure/config/app.yaml` |
| Feed Analyser (legacy) | `/feed_analyser/archive/` (legacy branch) |
| Capture Instrument | `/feed_analyser/capture/extension/`, `/feed_analyser/capture/server/` |
| Workspace Portability | `/workspace-portability/magic-setup.sh`, `/workspace-portability/backup_artifact.sh` |
| Headroom-pi | `/headroom-pi/install.sh`, `/headroom-pi/systemd/` |