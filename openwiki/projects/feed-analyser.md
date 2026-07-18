---
type: Project
title: Feed Analyser
description: Ingests curated feeds (Twitter, YouTube), classifies them via LLM, scouts for GitHub projects, and presents results in a React dashboard.
tags: [feed, ingestion, classification, llm, fastapi, react]
resource: /feed_analyser
---

# Feed Analyser

> From consumption to execution. Ingest curated feeds, distill actionable ideas, and deploy autonomous agents to evaluate and execute them.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Frontend (React/Vite :5174) — Human-in-the-Loop gate    │
│    └── Dashboard for review + manual trigger              │
├──────────────────────────────────────────────────────────┤
│  Backend (FastAPI :8000)                                  │
│    ├── Ingestion pipeline (JSON → SQLite)                 │
│    ├── Classification (LLM + heuristic fallback)          │
│    │    via: llm_client.WorkflowClient                    │
│    │    config/workflows.yaml                             │
│    ├── Scout (extract GitHub URLs, generate project cards)│
│    └── SQLite database (data.db)                          │
├──────────────────────────────────────────────────────────┤
│  Scripts/                                                 │
│    ├── twitter_console_scraper.js — Browser console scraper│
│    └── twitter_headless.py — Playwright-based scraper     │
├──────────────────────────────────────────────────────────┤
│  Runner Sandbox (Alpine, no internet)                     │
│    └── Isolated execution environment (reserved)          │
├──────────────────────────────────────────────────────────┤
│  LLM via: llm_client → llm/ server (:8012)               │
└──────────────────────────────────────────────────────────┘
```

## Pipeline

### 1. Ingest

Parses JSON files from `backend/raw_data/` into the SQLite database (`backend/data.db`). Supports Twitter/X data collected via:

- **Browser Console Scraper** (`scripts/twitter_console_scraper.js`) — Zero bot-detection risk, runs in your logged-in browser session. Paste script, type `start()`, get `.json` download.
- **Headless Scraper** (`scripts/twitter_headless.py`) — Playwright-based, requires exported session cookie file. Supports retweet scraping and profile feed scraping.

**Trigger:** Dashboard "Run Ingestion" button or `curl -X POST http://localhost:8000/api/sync`

### 2. Classify

Tags posts with categories and intent using:

- **Primary:** `client.complete_text("classify_tweet", prompt=...)` routes through the configured LLM via `llm_client.WorkflowClient`
- **Fallback:** YAML-configured fallback function (`heuristic_classify`) runs when the server is unreachable
- **Heuristics-only mode:** `CLASSIFY_HEURISTICS_ONLY=1` skips LLM entirely for bulk runs

**Trigger:** `curl -X POST http://localhost:8000/api/classify`

### 3. Scout

Extracts GitHub URLs from posts and generates project cards with summary information.

## LLM Integration

The feed analyser uses the shared [llm-client](/openwiki/projects/llm-server-client.md) package:

```python
from llm_client import WorkflowClient

client = WorkflowClient("config/workflows.yaml")
result = client.complete_text("classify_tweet", prompt=tweet_text)
```

Workflow configuration in `config/workflows.yaml` specifies model reference, temperature, output format (json/text), and optional fallback function.

## Services

| Service | Port | Purpose |
|---------|------|---------|
| Dashboard UI | 5174 | React/Vite frontend |
| Backend API | 8000 | FastAPI + SQLite |
| Database UI | 8088 | sqlite-web for inspection |
| Sandbox | — | Isolated Alpine container (reserved) |

## Startup

```bash
# Podman (default)
./start.sh

# Docker fallback
CONTAINER_RUNTIME=docker ./start.sh
```

The script builds images, creates networks, starts all services, and waits for health checks.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_RUNTIME` | `podman` | Container engine |
| `LLM_INFERENCE_URL` | `http://host.containers.internal:8012` | LLM server endpoint |

## Backlog for Future Extension

Per [/tasks.txt](/tasks.txt), the planned extensions are:

- YouTube feed ingestion
- Gmail feed ingestion
- GDrive feed ingestion

## Source Files

| File | Purpose |
|------|---------|
| `/feed_analyser/backend/` | FastAPI application |
| `/feed_analyser/frontend/` | React/Vite dashboard |
| `/feed_analyser/scripts/twitter_console_scraper.js` | Browser console scraper |
| `/feed_analyser/scripts/twitter_headless.py` | Playwright scraper |
| `/feed_analyser/config/workflows.yaml` | LLM workflow configuration |
| `/feed_analyser/docker-compose.yml` | Compose stack |
| `/feed_analyser/start.sh` | Startup script |
| `/feed_analyser/data.db` | SQLite database |
| `/feed_analyser/vision.md` | Vision document |
