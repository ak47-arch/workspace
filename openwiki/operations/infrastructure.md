---
type: Operations
title: Operations and Infrastructure
description: Headroom compression proxy, workspace backup/restore pipeline, and shared container runtime configuration for the workspace ecosystem.
tags: [operations, containers, backup, proxy, infrastructure]
resource: /
---

# Operations & Infrastructure

This page covers the shared operational infrastructure that keeps the workspace ecosystem running: the Headroom compression proxy for the pi coding agent, the workspace-portability backup/restore system, and the shared container runtime setup.

## Headroom Compression Proxy

**Project:** `/headroom-pi/`  
**Upstream:** [Headroom OSS](https://github.com/chopratejas/headroom) (in `/opensource/headroom/`)

[Headroom-pi](/headroom-pi) routes all pi coding agent traffic through Headroom's context compression proxy, achieving **60–95% fewer tokens (for JSON data), 15-20% fewer tokens (for coding agents)** with zero code changes.

### Architecture

```
pi → headroom-pi → Headroom proxy (:8787) → OpenRouter / Anthropic / OpenAI
                        │
                        ├─ SmartCrusher (JSON compression)
                        ├─ CodeCompressor (AST-based)
                        ├─ Kompress-base (ML text compression)
                        ├─ CacheAligner (KV cache hits)
                        └─ CCR (reversible — LLM retrieves originals)
```

### Installation

```bash
cd headroom-pi
./install.sh
```

The installer:
1. Finds or installs the `headroom` binary
2. Installs a systemd user service for the proxy (auto-restart on crash)
3. Adds a health-check timer (every 60s)
4. Installs the `headroom-pi` shell wrapper
5. Adds shell alias `pi=headroom-pi`
6. Configures `~/.pi/agent/models.json` to route through Headroom

### Commands

| Command | Purpose |
|---------|---------|
| `headroom-pi --status` | Show proxy version, uptime, port |
| `headroom-pi --restart` | Bounce the proxy, then launch pi |
| `headroom-pi --stop` | Stop the proxy service |
| `headroom-pi --no-proxy` | Launch pi without compression (escape hatch) |
| `systemctl --user status headroom-proxy.service` | Proxy health |

### Key Files

| File | Purpose |
|------|---------|
| `/headroom-pi/install.sh` | Full installer |
| `/headroom-pi/systemd/` | Systemd unit files |
| `/headroom-pi/extensions/` | Pi extension (macOS alternative) |
| `/headroom-pi/scripts/` | Helper scripts |

## Workspace Portability

**Project:** `/workspace-portability/`

The workspace-portability system provides comprehensive backup, recovery, bootstrap, setup, startup, and verification for the entire workspace.

### Architecture

**Phase 1 — Automatic (no user input required):**

```
magic-setup.sh → bootstrap-orchestrator.sh
  • Install git + curl
  • Clone workspace-portability
  • Clone workspace root + all sub-repos
  • Restore critical runtime data from GitHub Release
```

**Phase 2 — Interactive:**

```
setup-guide.sh
  • Profile selection (laptop, cloud-app, llm-node, ...)
  • Host dependency install
  • Secrets materialization (guided API key entry)
  • Large asset hydration (models)
  • Repo dependency install (pip, npm, pnpm)
  • Service startup
  • Health verification
```

### Canonical Entrypoints

| Script | Purpose |
|--------|---------|
| `magic-setup.sh` | Layer 0 — curl-able entrypoint for blank machines |
| `bootstrap-orchestrator.sh` | Layer 1 — clone repos + restore critical data |
| `full-restore.sh /path/to/workspace --start` | Full restore + setup + start |
| `setup-guide.sh` | Interactive guided setup |
| `backup_artifact.sh` | Create backup artifact |

### Snapshot Management

| Script | Purpose |
|--------|---------|
| `create-snapshot.sh` | Critical snapshot (dual-write: GDrive + GitHub) |
| `create-large-assets-snapshot.sh` | Large-assets snapshot (models) |
| `create-all-snapshots.sh` | Create both snapshots |
| `test-restore.sh` | Restore drill using latest local artifacts |

### Source Files

| File | Purpose |
|------|---------|
| `/workspace-portability/magic-setup.sh` | curl-able Phase 1 entrypoint |
| `/workspace-portability/bootstrap-orchestrator.sh` | Clone + restore |
| `/workspace-portability/full-restore.sh` | Full orchestrated restore |
| `/workspace-portability/setup-guide.sh` | Interactive Phase 2 |
| `/workspace-portability/backup_artifact.sh` | Backup artifact creation |
| `/workspace-portability/restore_data.py` | Python data restore logic |
| `/workspace-portability/restore_workspace.py` | Python workspace restore |
| `/workspace-portability/setup_workspace.py` | Python setup helpers |
| `/workspace-portability/start_services.py` | Service startup orchestration |
| `/workspace-portability/verify_workspace.py` | Verification logic |
| `/workspace-portability/portability_lib.py` | Shared portability library |
| `/workspace-portability/profiles/` | Machine profiles |

## Shared Container Runtime

All projects in the workspace use a consistent container strategy:

- **Default runtime:** Podman
- **Fallback:** Docker (set `CONTAINER_RUNTIME=docker`)
- **Shared network:** `workspace-shared-llm-network` (created automatically by `start_stack.sh` or manually)
- **Rootless:** UID/GID environment variables for file ownership

### Container Patterns

| Project | Entrypoint | Networking |
|---------|-----------|------------|
| LLM Server | `docker-compose.yml` in `/llm/` | Part of shared network |
| Survival Infra | `Makefile` → compose | Connects to LLM via shared network |
| Feed Analyser | `start.sh` → compose | Uses `host.containers.internal` for LLM access |
| Resume Editor | `podman compose up` or `run.sh` | Standalone |

## Known Issues

- **PYTHONPATH mount hack** — `llm_client` is volume-mounted into survival-infrastructure and feed_analyser containers via `PYTHONPATH` rather than baked into images. Fragile across directory layouts.
- **`compose_env_preflight.sh` missing** — Deleted during migration, breaking `start_stack.sh`. Workaround: `docker-compose up -d` directly.
- See [KNOWN_ISSUES.md](/KNOWN_ISSUES.md) for full tracking.