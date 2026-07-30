---
type: Entrypoint
title: Workspace Root Quickstart
description: Entrypoint for the workspace root project — a personal coding-agent infrastructure ecosystem with a centralized LLM inference server, data pipeline apps, session monitoring, and backup/restore tooling.
tags: [workspace, quickstart, llm, personal-infrastructure]
---

# Workspace Root Quickstart

This workspace is the home of a personal coding-agent infrastructure ecosystem. It contains a centralized [LLM inference server](/openwiki/projects/llm-server-client.md), two downstream data pipeline apps, a context compression proxy for the pi coding agent, and comprehensive backup/restore tooling — all wired together through container networking and a shared `llm_client` package.

## Quick Navigation

| Page | What it covers |
|------|----------------|
| [Architecture Overview](/openwiki/architecture/overview.md) | Cross-project dependency map, data flow, shared infrastructure |
| [LLM Server & Client](/openwiki/projects/llm-server-client.md) | Inference server, `llm_client` package, providers, prompt capture |
| [Survival Infrastructure](/openwiki/projects/survival-infrastructure.md) | Personal intelligence pipeline (capture → extract → wiki) |
| [Feed Analyser](/openwiki/projects/feed-analyser.md) | Feed ingestion (Twitter/YouTube), classification, sandbox |
| [Operations & Infrastructure](/openwiki/operations/infrastructure.md) | Headroom compression proxy, workspace backup/restore, containers |
| [Agent Configuration](/openwiki/reference/agent-config.md) | Skills, root config, tasks, known issues |

## Repository Layout

```
workspace/                    # Root (workspace-omp-local-tools)
├── llm/                      # Shared inference server + llm_client package
├── survival-infrastructure/  # Personal intelligence pipeline
├── feed_analyser/            # Feed ingestion & analysis
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
2. **Thorough testing** — Expand test coverage across all projects
3. **Agent containerisation** — Containerise coding agent workflows
4. **Think about survival infrastructure extension** — Extend pipeline stages
5. **Extend feed analyser with YouTube** — Add YouTube ingestion
6. **Implement GitHub browser authentication flow for project restore** — (workspace-portability) In PRD queue
7. **Set up themistocles** — Secondary Debian host to offload compute from laptop
8. **Work on headroom-pi** — Get it working reliably and run evals
9. **Think about automated monitoring** — Software factory monitoring automation
10. **People profiles in survival-infrastructure** — Work on people profiles
11. **Standardise documentation structure** — Across all apps
12. **Vision, functional, technical documentation** — Make projects factory-ready
13. **Plan modularisation of all apps** — Consistent project structure
14. **Update workspace portability** — With latest opensource projects
15. **Integrate Langfuse** — Observability/tracing for all applications
16. **Extend software_factory architecture** — Based on learnings from advanced context engineering
16. **Extend survival-infrastructure with Gmail and GDrive** — New instruction sources
17. **Deprecate spec-driven process** — For all projects
18. **Evaluate opensource/cognee integration** — Assess benefits for ecosystem
19. **Improve shared context infrastructure** — Add architecture design step
20. **Define projects clearly** — For efficient context infrastructure
21. **Make feed_analyser and survival_infrastructure private repos** — With current opensource repos
22. **Create personal website and blog** — Add toTweet, toBlog, toVideo pipeline (resume)
23. **Set up Langfuse agentically** — Use and operate Langfuse via agents

Completed tasks:
- Add script to update workspace_portability with latest opensource repos
- Create save-knowledge skill — Summarise session learnings and attach context window link
- Clean up project root — Move open source projects to separate directory
- Set up Langfuse — Fix langfuse-tracing.ts extension

## Backlog

- **timesheetViewer/** — Spring Boot app for Excel timesheet validation. Deferred: standalone project, not part of the core LLM/data-pipeline ecosystem. See its [README](/timesheetViewer/README.md).
- **resume/** — Flask Markdown resume editor. Deferred: personal productivity tool, not part of the infrastructure ecosystem. See its [README](/resume/README.md).
- **emotional_architecture/** — Personal operating manual, code of conduct, and relationship templates. Deferred: personal documents, not code documentation. See [/emotional_architecture/functional/](/emotional_architecture/functional/).
- **Individual OSS contrib repos** — Deferred: documented as a list below; deep coverage deferred to their own repositories.

## Knowledge Base

A new session-based knowledge base at `/docs/knowledge/` captures architectural decisions, tool evaluations, and session learnings via the `save-knowledge` skill. Each entry includes a freeform summary and the full session JSONL.

Current entries:
- [Browser Automation Tools: agent-browser vs web-search skill](/docs/knowledge/browser-automation/2026-07-21-agent-browser-vs-web-search-skill/summary.md)
- [Knowledge Base as Infrastructure Layer](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#1-knowledge-base-as-infrastructure-layer)
- [Product/Architecture as UX Layer](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#2-productarchitecture-as-ux-layer--two-artifact-outputs)
- [Progressive Disclosure Chain](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#3-progressive-disclosure-chain-for-agent-context)
- [Structured Decision Format](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#4-structured-decision-capture-format)
- [Session-Grouped Knowledge Structure](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#5-session-grouped-knowledge-directory-structure)
- [Model-Proactive Capture](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#6-model-proactive-decision-capture)
- [Skills as Packaging with disable-model-invocation](/docs/knowledge/sessions/019f8faf-c8f2-7612-a79d-10e18e6f78cf/decisions/01-factory-architecture-decisions.md#7-skills-as-packaging-layer-with-disable-model-invocation)
- [GitHub Browser Auth Flow for Workspace Restore](/docs/knowledge/sessions/019f937c-9afe-731e-a70d-c88d4eb9d675/decisions/01-github-browser-auth-flow.md)
- [Parallel Repo Clone](/docs/knowledge/sessions/019f93aa-ee32-7014-b963-8bec75928d5d/decisions/01-parallel-repo-clone.md)
- [Capture Instrument Architecture](/docs/knowledge/sessions/019f9487-9ea0-7905-8ae6-eaa2aff6bbdd/decisions/01-capture-instrument-architecture.md)
- [Extension Platform and UX](/docs/knowledge/sessions/019f9487-9ea0-7905-8ae6-eaa2aff6bbdd/decisions/02-extension-platform-and-ux.md)
- [Artefact Data Model and Storage](/docs/knowledge/sessions/019f9487-9ea0-7905-8ae6-eaa2aff6bbdd/decisions/03-artefact-data-model-and-storage.md)
- [Opensource Repo Manifest Registration Skill Design](/docs/knowledge/sessions/019fa31b-694b-7f94-ad00-bbc57a0c88df/decisions/01-opensource-repo-manifest-registration-skill.md)
- [Legacy Feed Analyser Archiving](/docs/knowledge/sessions/019f9487-9ea0-7905-8ae6-eaa2aff6bbdd/decisions/04-legacy-feed-analyser-archiving.md)
- [GDrive Integration Model and Source Type](/docs/knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/decisions/01-gdrive-integration-model.md)
- [GDrive Auth and Configuration Approach](/docs/knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/decisions/02-gdrive-auth-and-configuration.md)
- [GDrive File Export, Dedup, and Metadata Strategy](/docs/knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/decisions/03-gdrive-file-export-and-storage.md)
- [Voice Input to Pi via whisper.cpp](/docs/knowledge/sessions/019fa825-a262-7020-afec-0c733d21536d/decisions/01-voice-input-via-whisper-cpp.md)

## Open-Source Projects (in `/opensource/`)

The workspace tracks 25+ external open-source projects:

| Project | Description | Active Use |
|---------|-------------|------------|
| [headroom](https://github.com/chopratejas/headroom) | Context compression layer for AI agents (60-95% token reduction) | Core dependency of headroom-pi |
| [herdr](https://herdr.dev) | Terminal workspace manager / agent multiplexer | Core — pane management across the workspace |
| [openwiki](https://github.com/langchain-ai/openwiki) | CLI for writing/maintaining agent wikis | Actively generating this documentation |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | Browser automation CLI for AI agents | Referenced; evaluated in knowledge base |
| [graphify](https://github.com/ak47-arch/graphify) | Code graph analysis tool | Analysis output in /graphify-out/ |
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
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | C++ speech-to-text engine | Core — transcribe skill uses it for voice input to pi |
| agent-skills | Agent skills repository (symlinked to .agents/skills/web-search) | External |
| open-notebook | Submodule/alias | Referenced |
