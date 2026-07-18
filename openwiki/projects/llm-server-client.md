---
type: Project
title: LLM Inference Server and Client
description: Centralized inference server (Flask) with pluggable providers and a uniform pip-installable workflow client used by all downstream apps.
tags: [llm, inference, client, openai-compatible, flask]
resource: /llm
---

# LLM Inference Server & Client

The `llm/` directory contains two tightly-related components:

1. **Inference Server** — A Flask app exposing an OpenAI-compatible `/v1/chat/completions` endpoint with config-driven provider registration, managed server lifecycle, and prompt capture.
2. **llm_client** — A pip-installable package (`llm-client`) that provides a uniform `WorkflowClient` for calling LLM workflows with config-driven model selection, fallback, and response parsing.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  llm/ service_app.py on :8012                   │
│                                                 │
│  ProviderRouter (router.py)                     │
│    ├── openai_compatible_provider.py            │
│    │     (HTTP to any OpenAI-compatible backend) │
│    └── llama_cpp_provider.py                    │
│          (direct llama-cli subprocess)          │
│                                                 │
│  local_server_runtime.py                        │
│    (manages llama-server lifecycle per provider) │
│                                                 │
│  prompt_capture.py + capture_sinks.py           │
│    (optional durable prompt/asset capture)      │
│                                                 │
│  monitoring.py                                  │
│    (Prometheus metrics on /metrics)             │
└──────────────────────┬──────────────────────────┘
                       │ HTTP :8012
                       ▼
┌─────────────────────────────────────────────────┐
│  llm_client package (pip install llm-client)     │
│  WorkflowClient(config/workflows.yaml)          │
│    - Model definitions + URLs                    │
│    - Workflow definitions (temperature, output)  │
│    - Fallback chains                              │
│    - Auto JSON parsing                            │
└──────────────────────┬──────────────────────────┘
                       │ pip install
                       ▼
              Used by survival-infrastructure
              and feed_analyser
```

## Inference Server

### Entrypoint

`/llm/service_app.py` — Flask application serving:

- `GET /health` — Liveness
- `GET /ready` — Readiness (warmup)
- `GET /openapi.json` — OpenAPI contract
- `GET /v1/models` — Available models
- `POST /v1/chat/completions` — OpenAI-compatible inference
- `GET /metrics` — Prometheus metrics

### Provider System

Configuration is driven by `/llm/service_models.yaml`. The current active provider is `gemma_e2b_q4_local`:

```yaml
providers:
  - id: gemma_e2b_q4_local
    provider_type: openai_compatible
    model_name: gemma_e2b_q4_local
    capabilities:
      input_modalities: [text, image]
    connection:
      base_url: http://127.0.0.1:18012
      managed_server:
        binary_path: /opt/llama-cpp/llama-server
        model_path: /models/google_gemma-4-E2B-it-Q4_K_M.gguf
        port: 18012
        threads: 4
        startup_timeout_seconds: 180
```

Provider types:
- **openai_compatible** (`/llm/openai_compatible_provider.py`) — Calls any OpenAI-compatible HTTP backend. Supports `managed_server` for auto-launching a local `llama-server` process.
- **llama_cpp** (`/llm/llama_cpp_provider.py`) — Runs `llama-cli` directly through a subprocess for one-shot inference.

### Managed Server Lifecycle

`/llm/local_server_runtime.py` manages local `llama-server` processes:

- Starts `llama-server` as a child process with the configured model, port, threading, and mmproj path
- Health-checks via `/health` and `/v1/models` endpoints
- Returns `CompletionResult` with latency and token count
- Configured via `managed_server` block in `service_models.yaml`

### Prompt Capture

Optional durable capture of chat-completions traffic:

| Env Var | Purpose |
|---------|---------|
| `LLM_CAPTURE_ENABLED=true` | Enable capture |
| `LLM_CAPTURE_MODE=metadata` or `full` | What to store |
| `LLM_CAPTURE_SINK=ndjson` | Output format |
| `LLM_CAPTURE_FILE_PATH` | Output file path |
| `LLM_CAPTURE_REDACTION_LEVEL=off|basic|strict` | Redaction |

### Monitoring

`/llm/monitoring.py` tracks:
- `llm_service_requests_total` — request count by route/model/provider/outcome
- `llm_service_latency_seconds` — latency histogram
- `llm_runtime_cpu_seconds` / `llm_runtime_memory_bytes` — managed server resource metrics

## llm_client Package

**Source:** `/llm/llm_client/`  
**Package name:** `llm-client` (v0.5.0)  
**Dependencies:** PyYAML, requests, pydantic  
**Install:** `pip install llm-client` or from source via `pip install ./llm`

### Core Types

- `WorkflowClient` — Main entrypoint. Loads a `config/workflows.yaml` and provides `complete_text()` and `complete_json()` methods.
- `WorkflowResult` — Dataclass with `data` (parsed output), `model_id`, `latency_ms`, `tokens_used`.
- `LLMClientError`, `LLMTimeoutError`, `LLMUnavailableError`, `LLMBadResponseError` — Typed exceptions for robust error handling.

### Workflow Configuration

Each downstream project owns a `config/workflows.yaml`:

```yaml
models:
  fast:
    url: "http://host.containers.internal:8012"
    model: "gemma_e2b_q4_local"
    timeout: 180
  quality:
    url: "http://llm-inference-server:8012"
    model: "gemma_e2b_q4_local"
    timeout: 300

workflows:
  extraction:
    model_ref: fast
    temperature: 0.0
    max_tokens: 160
    output: json
    system_prompt: "Extract structured event fields as JSON..."
    fallback: none
```

### Usage

```python
from llm_client import WorkflowClient, WorkflowResult

client = WorkflowClient("config/workflows.yaml")
result = client.complete_text("classify_tweet", prompt=tweet_text)
print(result.data)  # parsed JSON if output=json
```

## Tests

Test files are under `/llm/tests/`:

| File | Scope |
|------|-------|
| `test_generic_inference_server.py` | Server integration tests |
| `test_openai_compatible_provider.py` | Provider HTTP calls |
| `test_workflow_client.py` | Client workflow execution |
| `test_monitoring.py` | Metrics and monitoring |
| `test_multimodal_chat.py` | Multimodal (image/audio) input |
| `test_prompt_capture.py` | Prompt capture pipeline |
| `test_operational_logging.py` | Logging behavior |

## Known Issues

- **PYTHONPATH mount hack** — `llm_client` is volume-mounted into containers via `PYTHONPATH` rather than baked into Docker images. Fragile across directory layouts. Tracked in [KNOWN_ISSUES.md](/KNOWN_ISSUES.md) Issue 1.
- **Reasoning params locked at server level** — `--reasoning`, `--reasoning-budget`, `--reasoning-format` are startup-only `extra_args` in `service_models.yaml`. Cannot be controlled per-workflow. Tracked as Issue 4.
- **`compose_env_preflight.sh` missing** — The preflight script was deleted during migration, breaking `start_stack.sh`. Issue 3.

## Source Files

| File | Purpose |
|------|---------|
| `/llm/service_app.py` | Flask application entrypoint |
| `/llm/router.py` | Provider router (loads YAML, resolves providers) |
| `/llm/provider_base.py` | Abstract `BaseProvider` + `CompletionResult` |
| `/llm/openai_compatible_provider.py` | HTTP OpenAI-compatible provider |
| `/llm/llama_cpp_provider.py` | llama-cli subprocess provider |
| `/llm/local_server_runtime.py` | Managed llama-server lifecycle |
| `/llm/service_models.yaml` | Provider configuration |
| `/llm/monitoring.py` | Prometheus metrics |
| `/llm/prompt_capture.py` | Durable prompt capture |
| `/llm/capture_sinks.py` | NDJSON sink for captured data |
| `/llm/llm_client/workflow_client.py` | WorkflowClient implementation |
| `/llm/llm_client/config.py` | Config models for workflow YAML |
| `/llm/llm_client/schemas.py` | WorkflowResult and response types |
| `/llm/llm_client/errors.py` | Typed LLM exceptions |
| `/llm/pyproject.toml` | Package metadata for llm-client |
| `/llm/Dockerfile` | Container image |
| `/llm/docker-compose.yml` | Compose stack with shared network |
