---
type: Entrypoint
title: Workspace Root Quickstart
description: Entrypoint for the workspace root project — a personal coding-agent infrastructure ecosystem with a centralized LLM inference server, data pipeline apps, session monitoring, and backup/restore tooling.
tags: [workspace, quickstart, llm, personal-infrastructure]
---

# Workspace Root Quickstart

This workspace is the home of a personal coding-agent infrastructure ecosystem. It contains a centralized [LLM inference server](/openwiki/projects/llm-server-client.md), two downstream data pipeline apps, a Rust-based session monitor, a context compression proxy for the pi coding agent, and comprehensive backup/restore tooling — all wired together through container networking and a shared `llm_client` package.

## Quick Navigation

| Page | What it covers |
|------|----------------|
| [Architecture Overview](/openwiki/architecture/overview.md) | Cross-project dependency map, data flow, shared infrastructure |
| [LLM Server & Client](/openwiki/projects/llm-server-client.md) | Inference server, `llm_client` package, providers, prompt capture |
| [Survival Infrastructure](/openwiki/projects/survival-infrastructure.md) | Personal intelligence pipeline (capture → extract → wiki) |
| [Feed Analyser](/openwiki/projects/feed-analyser.md) | Feed ingestion (Twitter/YouTube), classification, sandbox |
| [Mission Control](/openwiki/projects/mission-control.md) | Rust-based session monitoring over herdr + pi signals |
| [Operations & Infrastructure](/openwiki/operations/infrastructure.md) | Headroom compression proxy, workspace backup/restore, containers |
| [Agent Configuration](/openwiki/reference/agent-config.md) | Skills, root config, tasks, known issues |

## Repository Layout

```
workspace/                    # Root (workspace-omp-local-tools)
├── llm/                      # Shared inference server + llm_client package
├── survival-infrastructure/  # Personal intelligence pipeline
├── feed_analyser/            # Feed ingestion & analysis
├── mission-control/          # Rust session monitor
├── headroom-pi/              # Headroom compression proxy for pi
├── workspace-portability/    # Backup/restore/bootstrap
├── emotional_architecture/   # Personal operating manual & code of conduct
├── resume/                   # Resume editor (Flask + PDF)
├── timesheetViewer/          # Timesheet viewer (Spring Boot)
├── graphify-out/             # Code graph analysis output
├── opensource/               # 13+ forked/referenced OSS projects
├── skills/                   # OpenWiki skills (migrate-wiki-to-okf, write-connector)
├── .agents/                  # Agent skills (ssh, survival-infra ops)
├── .pi/                      # Pi agent config, extensions, skills
├── AGENTS.md / CLAUDE.md     # OpenWiki references
├── tasks.txt                 # High-level task list
├── KNOWN_ISSUES.md           # Post-migration technical debt
├── PLAN_shared_llm_client.md # LLM client architecture plan
└── HEADROOM-PI-PLAN.md       # Headroom integration plan
```

## High-Level Task List

From [/tasks.txt](/tasks.txt):

1. **Common LLM API** — The shared `llm_client` package ([PLAN_shared_llm_client.md](/PLAN_shared_llm_client.md)) implements this; post-migration cleanup items tracked in [KNOWN_ISSUES.md](/KNOWN_ISSUES.md)
2. **Modularise all apps** — Extract independent concerns into reusable packages
3. **Thorough testing** — Expand test coverage across all projects
4. **Agent containerisation** — Containerise coding agent workflows
5. **Work on apps** — Continue feature development
6. **Survival infrastructure extension** — Extend pipeline stages
7. **Extend feed analyser** — Add YouTube, Gmail, GDrive ingestion
8. **Clean up project root** — Move open-source projects to `opensource/`, update workspace-portability
9. **Build shared context infrastructure** — Using OpenWiki
10. **Set up Langfuse** — Observability/tracing platform

## Backlog

- **timesheetViewer/** — Spring Boot app for Excel timesheet validation. Deferred: standalone project, not part of the core LLM/data-pipeline ecosystem. See its [README](/timesheetViewer/README.md).
- **resume/** — Flask Markdown resume editor. Deferred: personal productivity tool, not part of the infrastructure ecosystem. See its [README](/resume/README.md).
- **emotional_architecture/** — Personal operating manual, code of conduct, and relationship templates. Deferred: personal documents, not code documentation. See [/emotional_architecture/functional/](/emotional_architecture/functional/).
- **Individual OSS contrib repos** — Deferred: documented as a list below; deep coverage deferred to their own repositories.
- **opensource/ skills/** — Deferred: external skills repo.
- **opensource/Understand-Anything/** — Deferred: not yet inspected.
- **opensource/pi-mono/** — Deferred: pi monorepo, external.
- **opensource/anything-llm/** — Deferred: third-party LLM UI, external.
- **opensource/hunk/** — Deferred: external project.
- **opensource/Agent-Reach/** — Deferred: external project.

## Open-Source Projects (in `/opensource/`)

The workspace tracks 13 external open-source projects:

| Project | Description | Active Use |
|---------|-------------|------------|
| [headroom](https://github.com/chopratejas/headroom) | Context compression layer for AI agents (60-95% token reduction) | Core dependency of headroom-pi |
| [herdr](https://herdr.dev) | Terminal workspace manager / agent multiplexer | Core — mission-control collects signals from it |
| [openwiki](https://github.com/langchain-ai/openwiki) | CLI for writing/maintaining agent wikis | Actively generating this documentation |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | Browser automation CLI for AI agents | Referenced |
| [graphify](https://github.com/ak47-arch/graphify) | Code graph analysis tool | Analysis output in /graphify-out/ |
| [hermes](https://github.com/NomicOne-ai/hermes) | Multi-agent orchestration framework | Referenced |
| open-notebook | Submodule/alias | Referenced |
| pi-mono | Pi monorepo | External |
| anything-llm | Third-party LLM UI | External |
| hunk | Project | External |
| Agent-Reach | Project | External |
| Understand-Anything | Project | External |
| skills | External skills collection | External |
