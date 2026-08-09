---
type: Entrypoint
title: Workspace Root Quickstart
description: Entrypoint for the workspace root project — a personal coding-agent infrastructure ecosystem with a centralized LLM inference server, data pipeline apps, session monitoring, and backup/restore tooling.
tags: [workspace, quickstart, llm, personal-infrastructure]
---

# Workspace Root Quickstart

This workspace is the home of a personal coding-agent infrastructure ecosystem. It contains a centralized [LLM inference server](/openwiki/projects/llm-server-client.md), downstream data pipeline apps (a [capture instrument](/openwiki/projects/feed-analyser.md) and the [survival-infrastructure](/openwiki/projects/survival-infrastructure.md) pipeline), a context compression proxy for the pi coding agent, and comprehensive backup/restore tooling — all wired together through container networking and a shared `llm_client` package. The whole workspace is developed and maintained under a [software factory](/openwiki/projects/software-factory.md) paradigm.

## Quick Navigation

| Page | What it covers |
|------|----------------|
| [Architecture Overview](/openwiki/architecture/overview.md) | Cross-project dependency map, data flow, shared infrastructure |
| [LLM Server & Client](/openwiki/projects/llm-server-client.md) | Inference server, `llm_client` package, providers, prompt capture |
| [Survival Infrastructure](/openwiki/projects/survival-infrastructure.md) | Personal intelligence pipeline (capture → extract → wiki) |
| [Feed Analyser](/openwiki/projects/feed-analyser.md) | X/Twitter capture instrument (Chrome extension + local server); legacy feed analyser archived |
| [Software Factory](/openwiki/projects/software-factory.md) | Assembly-line paradigm: context engine, product layer, task lifecycle, sub-agent review gate |
| [Operations & Infrastructure](/openwiki/operations/infrastructure.md) | Headroom compression proxy, workspace backup/restore, containers |
| [Agent Configuration](/openwiki/reference/agent-config.md) | Skills, root config, tasks, known issues |

### Task Routing

| Change area / intent | Wiki page | Source entry points | Key symbols / types | Focused tests | Minimal validation |
|----------------------|-----------|--------------------|---------------------|---------------|--------------------|
| Task lifecycle / PRD workflow | [Software Factory](/openwiki/projects/software-factory.md) | `bin/transition-task.sh`, `docs/tasks/<slug>.md`, `docs/prd-queue/` | transition states, `--to`, `--dry-run` | `bin/test-transition-task.sh` | `bin/test-transition-task.sh` |
| Add a plan/PRD | [Software Factory](/openwiki/projects/software-factory.md) | `/.agents/skills/product-layer/SKILL.md` | task `slug`, category Small/Medium/Large | — | follow skill: grill → capture → `transition-task.sh <slug> --to prd-ready` |
| PRD review gate / sub-agent | [Software Factory](/openwiki/projects/software-factory.md) | `/.pi/extensions/subagent/`, `/.pi/agents/prd-reviewer.md` | `prd-reviewer`, `agentScope`, `tools` | — | live pi session: `/reload` + invoke agent |
| herdr subagent hang fix | [Agent Configuration](/openwiki/reference/agent-config.md) | `/.pi/extensions/herdr-agent-state.ts` | heartbeat interval `unref()` + `clearInterval` | — | run a subagent in `--mode json` and confirm clean exit |
| Pi extensions / settings | [Agent Configuration](/openwiki/reference/agent-config.md) | `/.pi/settings.json`, `/.pi/extensions/` | `langfuse-tracing` | — | `pi` starts; `git log` confirms wiring |

The projects below (LLM, survival-infrastructure, feed-analyser/capture) have their own `openwiki/` inside each sub-repo; follow the per-project links for deep code-level change guidance.

## Repository Layout

```
workspace/                    # Root (workspace-omp-local-tools)
├── llm/                      # Shared inference server + llm_client package
├── survival-infrastructure/  # Personal intelligence pipeline
├── feed_analyser/            # Capture instrument (extension + server); legacy app archived
├── headroom-pi/              # Headroom compression proxy for pi
├── workspace-portability/    # Backup/restore/bootstrap
├── emotional_architecture/   # Personal operating manual & code of conduct
├── resume/                   # Resume editor (Flask + PDF)
├── timesheetViewer/          # Timesheet viewer (Spring Boot)
├── opensource/               # 25+ forked/referenced OSS projects
├── bin/                      # Factory tooling: transition-task.sh, backfill, index sort
├── .agents/                  # Agent skills (product-layer, save-knowledge, ssh, transcribe, ...)
├── .pi/                      # Pi agent config, extensions (incl. subagent), agents
├── docs/                     # factory-context, tasks, prd-queue/archive, knowledge base
├── AGENTS.md / CLAUDE.md     # OpenWiki + software-factory references
└── (plans live in their projects) # /llm/PLAN_shared_llm_client.md, /headroom-pi/HEADROOM-PI-PLAN.md
```

## High-Level Task List

From [/docs/tasks.txt](/docs/tasks.txt) — tasks are organised **by project, then by status** (Pending / Queued / Complete). This summary reflects the state as of 2026-08-09. See the [Software Factory](/openwiki/projects/software-factory.md) page for the lifecycle model and task-tracking mechanics.

Cross-project (pending):
- Thorough testing, agent containerisation, standardise documentation structure, vision/functional/technical docs, modularise all apps, integrate Langfuse with all applications, deprecate spec-driven process

Selected project tasks:
- **software-factory**: automated monitoring thinking, opensource/cognee evaluation, improve shared context infrastructure, add task-selection abstraction layer, build the implementer agent, extend the prod review agent (all pending)
- **feed-analyser (queued)**: `extension-inline-agent` — add a pi agent to the extension with access to content and URLs
- **survival-infrastructure**: think about extension, people profiles, audio event ingestion via whisper.cpp (pending); Gmail+GDrive instruction sources (queued)
- **workspace-portability**: set up themistocles, update with latest opensource projects, move everything to a cloud instance (pending)
- **headroom-pi**: work on it and run evals (pending)
- **resume**: personal website and blog with toTweet/toBlog/toVideo pipeline (pending)
- **langfuse**: integrate official skill and operate Langfuse agentically (pending)

Recently completed: `extend-pm-assembly-line`, `x-capture-instrument` (UAT passed, PRD archived), `task-file-dashboard`, `combine-factory-context-factory-txt`, `chronological-tracking`, `extend-software-factory-wsff`, `end-to-end-traceability`, `vision-task-traceability`, `github-browser-auth-flow`, `feed-analyser-survival-infra-private-repos`.

## Backlog

- **timesheetViewer/** — Spring Boot app for Excel timesheet validation. Deferred: standalone project, not part of the core LLM/data-pipeline ecosystem. See its [README](/timesheetViewer/README.md).
- **resume/** — Flask Markdown resume editor. Deferred: personal productivity tool, not part of the infrastructure ecosystem. See its [README](/resume/README.md).
- **emotional_architecture/** — Personal operating manual, code of conduct, and relationship templates. Deferred: personal documents, not code documentation. See [/emotional_architecture/functional/](/emotional_architecture/functional/).
- **Individual OSS contrib repos** — Deferred: documented as a list below; deep coverage deferred to their own repositories.

## Knowledge Base

A session-based knowledge base at [`/docs/knowledge/index.md`](/docs/knowledge/index.md) captures architectural decisions, tool evaluations, and session learnings via the `save-knowledge` skill, organised **by project**. Each entry is a structured decision record (`Context` / `Decision` / `Rationale` / `Consequences` / `Revision triggers`) linking to the full session `session.jsonl`. The OKF-compliant [Agent Configuration](/openwiki/reference/agent-config.md) page and [Software Factory](/openwiki/projects/software-factory.md) page point into it; it is the deliberate "last resort" layer in the factory's progressive-disclosure chain.

Representative decisions added since 2026-07-29:
- **software-factory**: [PRD as Routing Document + Review Sub-Agent Gate](/docs/knowledge/sessions/019fd00b-4e86-76ed-966b-186ea09c775c/decisions/01-prd-as-routing-document-context-engine-depth.md), [Subagent Infrastructure — Official Pi Extension, Project-Local, Read-Only Reviews](/docs/knowledge/sessions/019fd00b-4e86-76ed-966b-186ea09c775c/decisions/04-subagent-infrastructure-pi-extension-project-local.md), [Temporal Metadata Convention](/docs/knowledge/sessions/019fc389-c171-7c69-9eeb-6100abd6bc87/decisions/01-temporal-metadata-convention.md), [Reliable Lifecycle Transition Script with Test Suite](/docs/knowledge/sessions/019fbd12-7ea3-7152-9eec-f865cf69d6f7/decisions/03-reliable-transition-script-with-tests.md), [PRD status lifecycle — Final when the review gate passes](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/07-prd-status-lifecycle.md), [Subagent handover hang — herdr heartbeat fix](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/08-subagent-handover-hang-herdr.md)
- **feed-analyser (capture)**: [PI SDK agent service](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/01-pi-sdk-agent-service.md), [Capture artefact is a recursive node tree](/docs/knowledge/sessions/019fd314-9339-7a30-9b8b-f6d8892b5226/decisions/04-capture-recursive-node-tree-comment-is-tweet.md), [Plain files as truth + SQLite FTS5 read API](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/05-twitter-kb-plain-files-fts5-read-api.md)
- **workspace-portability**: [GitHub Device Authorization Flow Implementation](/docs/knowledge/sessions/019faf44-901a-73f9-aa74-817eead12980/decisions/01-github-device-auth-flow-implementation.md), [Device Flow End-to-End Test Verification](/docs/knowledge/sessions/019faf44-901a-73f9-aa74-817eead12980/decisions/02-device-flow-test-verification.md)

The full, always-current list lives in [`/docs/knowledge/index.md`](/docs/knowledge/index.md).

## Open-Source Projects (in `/opensource/`)

The workspace tracks 25+ external open-source projects:

| Project | Description | Active Use |
|---------|-------------|------------|
| [headroom](https://github.com/chopratejas/headroom) | Context compression layer for AI agents (60-95% token reduction) | Core dependency of headroom-pi |
| [herdr](https://herdr.dev) | Terminal workspace manager / agent multiplexer | Core — pane management across the workspace |
| [openwiki](https://github.com/langchain-ai/openwiki) | CLI for writing/maintaining agent wikis | Actively generating this documentation |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | Browser automation CLI for AI agents | Referenced; evaluated in knowledge base |
| [graphify](https://github.com/ak47-arch/graphify) | Code graph analysis tool | Referenced/in analysis |
| [hermes](https://github.com/NomicOne-ai/hermes) | Multi-agent orchestration framework | Referenced |
| [langfuse](https://github.com/langfuse/langfuse) | Observability/tracing platform for LLM apps | Planned integration; langfuse-tracing.ts extension |
| [open-notebook](https://github.com/luminai/open-notebook) | AI-powered research notebook | Referenced |
| [pi-mono](https://github.com/pi-mono/pi-mono) | Pi coding agent monorepo | External |
| [anything-llm](https://github.com/Mintplex-Labs/anything-llm) | Third-party LLM UI | External |
| [hunk](https://github.com/hunk/hunk) | Project | External |
| [Agent-Reach](https://github.com/Agent-Reach/Agent-Reach) | Project | External |
| [Understand-Anything](https://github.com/Understand-Anything/Understand-Anything) | Project | External |
| [skills](https://github.com/agent-skills/skills) | External skills collection | External |
| [woodpecker](https://github.com/woodpecker-ci/woodpecker) | CI/CD engine | Referenced |
| [yazi](https://github.com/sxyazi/yazi) | Terminal file manager | Referenced |
| [bitchat](https://github.com/bitchat/bitchat) | P2P messaging via Bluetooth mesh | Referenced |
| [bitchat-android](https://github.com/bitchat/bitchat-android) | Android client for bitchat | Referenced |
| [deepagents](https://github.com/...) | Deep agent framework | Referenced |
| [cognee](https://github.com/topoteretes/cognee) | Memory/knowledge engine for AI agents | Evaluation for ecosystem integration |
| [docetl](https://github.com/...) | Document ETL pipeline | Referenced |
| [pi-agent-browser-native](https://github.com/...) | Native browser agent for pi | Referenced |
| [ponytail](https://github.com/...) | Project | Referenced |
| [Handy](https://github.com/...) | Project | External |
| [prime-agent](https://github.com/...) | Project | External |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | C++ speech-to-text engine | Core — transcribe skill uses it for voice input to pi |
| agent-skills | Agent skills repository (symlinked to .agents/skills/web-search) | External |
| open-notebook | Submodule/alias | Referenced |
