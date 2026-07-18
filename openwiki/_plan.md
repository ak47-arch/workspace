---
type: Plan
title: OpenWiki Documentation Plan
description: Plan for initial workspace documentation
tags: [plan, workspace]
---

# OpenWiki Documentation Plan

## Intended Pages

### 1. /openwiki/quickstart.md
- Entrypoint with workspace overview
- Links to all section pages
- High-level task list (from /tasks.txt)
- Backlog for deferred areas

### 2. /openwiki/architecture/overview.md
- System architecture: centralized LLM server + downstream apps
- Data flow: capture → enrichment → storage → wiki
- Cross-project dependency map
- Shared infrastructure: network, container runtime, PYTHONPATH hacks

### 3. /openwiki/projects/llm-server-client.md
- LLM inference server (llm/): Flask app, router, providers, managed server lifecycle
- llm_client package: WorkflowClient, config-driven workflows
- Service models, prompt capture, monitoring
- Known issues: PYTHONPATH mount, reasoning params

### 4. /openwiki/projects/survival-infrastructure.md
- Pipeline: collection → extraction → storage → wiki synthesis
- API routes, data storage model
- LLM integration via llm_client
- Known issues: broken start_stack.sh, preflight script

### 5. /openwiki/projects/feed-analyser.md
- Feed ingestion (Twitter/YouTube)
- Classification pipeline with LLM + heuristic fallback
- Frontend/backend/sandbox architecture
- LLM integration via llm_client

### 6. /openwiki/projects/mission-control.md
- Rust workspace: mc-schema, mc-core, mc-binary
- herdr integration, pi signal collection
- Architecture: collectors → reducer → state → event emitter
- TUI and web dashboards

### 7. /openwiki/operations/infrastructure.md
- headroom-pi: compression proxy, systemd, pi integration
- workspace-portability: backup/restore/bootstrap
- Container runtime: Podman default, Docker fallback
- Shared network: workspace-shared-llm-network

### 8. /openwiki/reference/agent-config.md
- AGENTS.md / CLAUDE.md - OpenWiki references
- .pi/ settings, extensions, skills
- .agents/ skills (ssh-themistocles, survival-infrastructure-operation)
- tasks.txt, PLAN_shared_llm_client.md, KNOWN_ISSUES.md

## Evidence Sources

### Primary evidence
- /PLAN_shared_llm_client.md - LLM client architecture
- /HEADROOM-PI-PLAN.md - Headroom proxy integration
- /KNOWN_ISSUES.md - Post-migration cleanup
- /tasks.txt - High-level task list
- /AGENTS.md, /CLAUDE.md - OpenWiki references
- /package.json - workspace-omp-local-tools

### Sub-project READMEs
- /llm/README.md - Inference server docs
- /survival-infrastructure/README.md - Pipeline docs
- /feed_analyser/README.md - Feed analyser docs
- /headroom-pi/README.md - Compression proxy docs
- /mission-control/README.md - Mission control docs
- /workspace-portability/README.md - Portability docs
- /resume/README.md - Resume editor docs
- /timesheetViewer/README.md - Timesheet viewer docs

### Sub-project key files
- /llm/pyproject.toml - llm-client package definition
- /llm/service_models.yaml - Provider configuration
- /llm/llm_client/workflow_client.py - Shared client
- /llm/router.py - Provider routing
- /llm/service_app.py - Flask app entrypoint
- /llm/local_server_runtime.py - Managed server lifecycle
- /survival-infrastructure/config/app.yaml - App config
- /survival-infrastructure/app.py - Flask routes
- /mission-control/Cargo.toml - Rust workspace
- /mission-control/DESIGN.md - Architecture decisions
- /headroom-pi/install.sh - Installation script
- /workspace-portability/README.md - Full restore flow

### Agent config
- /.pi/settings.json - pi settings
- /.pi/extensions/ - pi extensions
- /.agents/skills/ssh-themistocles/SKILL.md - SSH skill
- /.agents/skills/survival-infrastructure-operation/SKILL.md - Survival infra skill

### Open-source projects
- /opensource/headroom/ - Context compression proxy
- /opensource/herdr/ - Terminal workspace manager
- /opensource/openwiki/ - OpenWiki documentation tool
- /opensource/agent-browser/ - Browser automation
- /opensource/hermes/ - Agent framework
- /opensource/graphify/ - Code graph analysis

## Relationship Map

| Source | Relationship | Target |
|--------|-------------|--------|
| llm/ | serves inference to | survival-infrastructure, feed_analyser |
| llm_client | shared package consumed by | survival-infrastructure, feed_analyser |
| headroom-pi | proxies traffic for | pi (coding agent) |
| headroom-pi | depends on | headroom (opensource) |
| mission-control | collects signals from | herdr (opensource), pi |
| survival-infrastructure | uses network for | llm (inference) |
| workspace-portability | backs up/restores | all sub-projects |
| feed_analyser | uses workflows.yaml from | llm_client |
| survival-infrastructure | uses workflows.yaml from | llm_client |
| /.agents/skills/ | agent skills for operating | survival-infrastructure, themistocles |
| /opensource/ | external OSS projects | forked/referenced |