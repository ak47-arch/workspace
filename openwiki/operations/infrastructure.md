---
type: Operations
title: Operations and Infrastructure
description: Headroom compression proxy, workspace backup/restore pipeline, shared container runtime configuration, the GitHub Actions headless factory workflow, and session sanitization for the workspace ecosystem.
tags: [operations, containers, backup, proxy, infrastructure, github-actions, ci]
resource: /
---

# Operations & Infrastructure

This page covers the shared operational infrastructure that keeps the workspace ecosystem running: the Headroom compression proxy for the pi coding agent, the workspace-portability backup/restore system, the shared container runtime setup, the GitHub Actions headless factory loop, and session sanitization.

## Headroom Compression Proxy

**Project:** `/headroom-pi/`  
**Upstream:** [Headroom OSS](https://github.com/chopratejas/headroom) (in `/opensource/headroom/`)

Headroom-pi routes all pi coding agent traffic through Headroom's context compression proxy, achieving **60–95% fewer tokens (for JSON data), 15-20% fewer tokens (for coding agents)** with zero code changes.

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
- **CI exception:** GitHub-hosted runners cannot start podman containers (instant exit 125), so the [headless factory loop](/openwiki/projects/software-factory.md) forces both agent legs to Docker via `IMPLEMENTER_PODMAN_BIN=docker` / `REVIEWER_PODMAN_BIN=docker`

### Container Patterns

| Project | Entrypoint | Networking |
|---------|-----------|------------|
| LLM Server | `docker-compose.yml` in `/llm/` | Part of shared network |
| Survival Infra | `Makefile` → compose | Connects to LLM via shared network |
| Feed Analyser | `start.sh` → compose | Uses `host.containers.internal` for LLM access |
| Resume Editor | `podman compose up` or `run.sh` | Standalone |
| Factory sandbox | `workspace-portability/container/Dockerfile` (built as `sandbox:latest`) | `--network=host` inside the host driver |

## GitHub Actions Workflows (`.github/workflows/`)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `factory.yml` | push to `docs/prd-queue/**.md`; `workflow_dispatch` with optional `task` slug | **Headless factory loop** — status gate (Final + `prd-ready`) → `bin/factory-run.sh --headless` → implementer → review → revise (cap 3, `REVISION_CAP`) → trace bundle to private `ak47-arch/factory-traces` → tracking sync to master. Single-run concurrency (`factory-headless`, `cancel-in-progress: false`). See [Software Factory](/openwiki/projects/software-factory.md). |
| `openwiki-update.yml` | scheduled | Regenerates this wiki (all pages under `openwiki/`) |

The factory workflow's runner seams are the load-bearing part: the classic PAT
`FACTORY_GH_PAT` is used **directly** as `GH_TOKEN` for `gh` and via a
`url."https://x-access-token:${PAT}@github.com/".insteadOf` rewrite for git —
never through `gh auth login` (which demands `read:org`), and never the
single-repo `GITHUB_TOKEN`. The **trace bundle** (raw sessions, streamed
transcript, container logs, driver trace, manifest) is pushed to the *private*
`ak47-arch/factory-traces` repo for eval retention; only **sanitized** session
copies ever land on the public workspace master (via `bin/sanitize-session.sh`,
see below). The final **tracking sync** step pushes docs/evidence commits to
master (`git add -A` → conflict-tolerant merge `-X theirs` → push) — metadata
only; code reaches master only via a human-merged PR.

## Session Sanitization (`bin/sanitize-session.sh`)

Session JSONL traces capture tool output (e.g. `cat ~/.config/gh/hosts.yml`,
env vars) that can embed live credentials. Committing those trips GitHub Push
Protection (GH013) and blocks the tracking commit, so the save-knowledge skill
and both factory drivers run every committed session copy through this script
before it lands in `docs/knowledge/sessions/`:

- Redacts values for `sk-or-v1-*` (OpenRouter), `sk-lf-*` (Langfuse),
  `gho_*` / `ghp_*` / `github_pat_*` (GitHub tokens), `xox*-*` (Slack),
  `AKIA*` (AWS) — prefix kept, value → `REDACTED`
- `--dry-run` prints the redaction count without modifying; exit 3 when
  unredacted secrets remain
- Raw, unredacted sessions are retained only in the private factory-traces
  bundle; never commit raw traces to the public repo

## Known Issues

- **PYTHONPATH mount hack** — `llm_client` is volume-mounted into survival-infrastructure and feed_analyser containers via `PYTHONPATH` rather than baked into images. Fragile across directory layouts.
- **`compose_env_preflight.sh` missing** — Deleted during migration, breaking `start_stack.sh`. Workaround: `docker-compose up -d` directly.
- **Factory CI sync step still `git add -A`** — decision 09 hardening (narrow to `git add docs/` + a non-merge code-path tripwire) is pending; a code file swept into the tracking sync would bypass the PR gate.
- See [KNOWN_ISSUES.md](/docs/KNOWN_ISSUES.md) for full tracking (now also covering factory-context issues and the file-based knowledge base).