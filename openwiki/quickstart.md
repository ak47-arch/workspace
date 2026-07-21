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
├── opensource/               # 18+ forked/referenced OSS projects
├── skills/                   # OpenWiki skills (migrate-wiki-to-okf, write-connector)
├── .agents/                  # Agent skills (ssh, survival-infra ops, save-knowledge)
├── .pi/                      # Pi agent config, extensions, skills
├── docs/                     # Project docs: tasks.txt, KNOWN_ISSUES.md, knowledge base
├── AGENTS.md / CLAUDE.md     # OpenWiki references
├── PLAN_shared_llm_client.md # LLM client architecture plan
└── HEADROOM-PI-PLAN.md       # Headroom integration plan
```

## High-Level Task List

From [/docs/tasks.txt](/docs/tasks.txt):

1. **Common LLM API** — The shared `llm_client` package ([PLAN_shared_llm_client.md](/llm/PLAN_shared_llm_client.md)) implements this; post-migration cleanup items tracked in [KNOWN_ISSUES.md](/docs/KNOWN_ISSUES.md)
2. **Modularise all apps** — Extract independent concerns into reusable packages
3. **Thorough testing** — Expand test coverage across all projects
4. **Agent containerisation** — Containerise coding agent workflows
5. **Think about survival infrastructure extension** — Extend pipeline stages
6. **Extend feed analyser** — Add YouTube, Gmail, GDrive ingestion
7. **Clean up project root** — Move open-source projects to `opensource/`, update workspace-portability — ✅ **Done**
8. **Build shared context infrastructure** — Using OpenWiki
9. **Set up Langfuse** — Observability/tracing platform
10. **Implement GitHub browser authentication flow** — For project restore
11. **Set up themistocles (secondary Debian host)** — Offload compute from laptop
12. **Work on headroom-pi** — Get it working reliably and run eval
13. **Create save-knowledge skill** — Summarise session learnings and attach context window link — ✅ **Done**

## Backlog

- **timesheetViewer/** — Spring Boot app for Excel timesheet validation. Deferred: standalone project, not part of the core LLM/data-pipeline ecosystem. See its [README](/timesheetViewer/README.md).
- **resume/** — Flask Markdown resume editor. Deferred: personal productivity tool, not part of the infrastructure ecosystem. See its [README](/resume/README.md).
- **emotional_architecture/** — Personal operating manual, code of conduct, and relationship templates. Deferred: personal documents, not code documentation. See [/emotional_architecture/functional/](/emotional_architecture/functional/).
- **Individual OSS contrib repos** — Deferred: documented as a list below; deep coverage deferred to their own repositories.

## Knowledge Base

A new session-based knowledge base at `/docs/knowledge/` captures architectural decisions, tool evaluations, and session learnings via the `save-knowledge` skill. Each entry includes a freeform summary and the full session JSONL.

Current entries:
- [Browser Automation Tools: agent-browser vs web-search skill](/docs/knowledge/browser-automation/2026-07-21-agent-browser-vs-web-search-skill/summary.md)

## Open-Source Projects (in `/opensource/`)

The workspace tracks 18+ external open-source projects:

| Project | Description | Active Use |
|---------|-------------|------------|
| [headroom](https://github.com/chopratejas/headroom) | Context compression layer for AI agents (60-95% token reduction) | Core dependency of headroom-pi |
| [herdr](https://herdr.dev) | Terminal workspace manager / agent multiplexer | Core — mission-control collects signals from it |
| [openwiki](https://github.com/langchain-ai/openwiki) | CLI for writing/maintaining agent wikis | Actively generating this documentation |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | Browser automation CLI for AI agents | Referenced; evaluated in knowledge base |
| [graphify](https://github.com/ak47-arch/graphify) | Code graph analysis tool | Analysis output in /graphify-out/ |
| [hermes](https://github.com/NomicOne-ai/hermes) | Multi-agent orchestration framework | Referenced |
| [langfuse](https://github.com/langfuse/langfuse) | Observability/tracing platform for LLM apps | Planned integration |
| [open-notebook](https://github.com/luminai/open-notebook) | AI-powered research notebook | Referenced |
| [pi-mono](https://github.com/pi-mono/pi-mono) | Pi coding agent monorepo | External |
| [anything-llm](https://github.com/Mintplex-Labs/anything-llm) | Third-party LLM UI | External |
| [hunk](https://github.com/hunk/hunk) | Project | External |
| [Agent-Reach](https://github.com/Agent-Reach/Agent-Reach) | Project | External |
| [Understand-Anything](https://github.com/Understand-Anything/Understand-Anything) | Project | External |
| [skills](https://github.com/agent-skills/skills) | External skills collection | External |
| [woodpecker](https://github.com/woodpecker-ci/woodpecker) | CI/CD engine | Referenced |
| [yazi](https://github.com/sxyazi/yazi) | Terminal file manager | Referenced |
| agent-skills | Agent skills repository (symlinked to .agents/skills/web-search) | External |
| open-notebook | Submodule/alias | Referenced |
