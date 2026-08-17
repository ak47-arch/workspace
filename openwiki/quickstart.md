---
type: Entrypoint
title: Workspace Root Quickstart
description: Entrypoint for the workspace root project — a personal coding-agent infrastructure ecosystem with a centralized LLM inference server, data pipeline apps, session monitoring, backup/restore tooling, and a software-factory assembly line now run headlessly on GitHub Actions.
tags: [workspace, quickstart, llm, personal-infrastructure, software-factory]
openwiki:
  roles: [architecture, domain, integration, operations, workflow]
  change_kinds: [lifecycle, public-api]
  source_paths: [bin/factory-run.sh, bin/implementer-run.sh, bin/review-run.sh, bin/transition-task.sh, .github/workflows/factory.yml]
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
| Implement the implementer / reviewer / factory ORCHESTRATION | [Software Factory](/openwiki/projects/software-factory.md) | `bin/implementer-run.sh`, `bin/review-run.sh`, `bin/factory-run.sh`, `bin/merge-pr.sh` | `--pick`, `--revise`, `--continue`, `--headless`, `factory:needs-review` label | `bin/test-implementer-driver.sh`, `bin/test-review-driver.sh`, `bin/test-factory-run.sh`, `bin/test-merge-pr.sh` | `bin/test-factory-run.sh` |
| Change the headless CI loop | [Software Factory](/openwiki/projects/software-factory.md) | `.github/workflows/factory.yml`, `bin/factory-run.sh` | status gate, `--headless`, REVISION_CAP, `FACTORY_GH_PAT`, trace bundle, tracking sync | `bin/test-factory-run.sh` | `bin/test-factory-run.sh` |
| Change task lifecycle / bundle transitions | [Software Factory](/openwiki/projects/software-factory.md) | `bin/transition-task.sh`, `docs/tasks/<slug>.md`, `docs/prd-queue/` | transition states, `--to`, multi-line `[slug]` bundles | `bin/test-transition-task.sh` | `bin/test-transition-task.sh` |
| Review a raised PR | [Software Factory](/openwiki/projects/software-factory.md) | `bin/review-run.sh` | `code-reviewer`, APPROVE / REQUEST_CHANGES (bare or markdown-bold) verdict | `bin/test-review-driver.sh` | `bin/review-run.sh --dry-run <pr>` |
| Add a plan/PRD | [Software Factory](/openwiki/projects/software-factory.md) | `/.agents/skills/product-layer/SKILL.md` | task `slug`, category Small/Medium/Large, similarity check / merge bundle | — | follow skill: grill → capture → `transition-task.sh <slug> --to prd-ready` |
| PRD review gate / sub-agent | [Software Factory](/openwiki/projects/software-factory.md) | `/.pi/extensions/subagent/`, `/.pi/agents/prd-reviewer.md` | `prd-reviewer`, `agentScope`, `tools` | — | live pi session: `/reload` + invoke agent |
| Add / extend an assembly-line skill | [Agent Configuration](/openwiki/reference/agent-config.md) | `/.agents/skills/<name>/SKILL.md` | run-contract conventions (`implementer-ops`, `review-ops`, `implementer-save`) | driver test suites | driver test suite for the skill's driver |
| Session redaction before commit | [Agent Configuration](/openwiki/reference/agent-config.md) | `bin/sanitize-session.sh`, `/.agents/skills/save-knowledge/SKILL.md` | `sk-or-v1-*`, `gho_*`, `ghp_*`, `github_pat_*`, `AKIA*` | — | `bash bin/sanitize-session.sh --dry-run <session.jsonl>` |
| Pi extensions / settings | [Agent Configuration](/openwiki/reference/agent-config.md) | `/.pi/settings.json`, `/.pi/extensions/` | `langfuse-tracing`, `herdr-agent-state` | — | `pi` starts; `git log` confirms wiring |

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

Recent additions (software-factory): the **headless factory loop** — `.github/workflows/factory.yml` runs `bin/factory-run.sh --headless` on GitHub Actions whenever a **Final** PRD with a `prd-ready` task is pushed (status gate, containerized implementer + reviewer, revise-until-APPROVE with a cap of 3, per-run trace bundles pushed to private `factory-traces`, and a tracking/evidence sync to master). Hardening since: sandbox agents resolve LLM credentials from `~/.pi/agent/auth.json`, committed session copies are sanitized via `bin/sanitize-session.sh` (GH013 guard), delivery failures are loud (exit 1 + task revert instead of false success), the verdict parse matches markdown-bold tokens, `transition-task.sh` moves merge-bundle `[slug]` lines per-project, and decision 09 gates code to master behind human-merged PRs.

Selected project tasks:
- **software-factory**: automated monitoring thinking, opensource/cognee evaluation, improve shared context infrastructure, add task-selection abstraction layer, extend the prod review agent, no-prompt-before-delete infrastructure, build the factory into its own product with evals, host apps in test/main/prod environments, save compressed sessions (all pending)
- **feed-analyser**: `extension-inline-agent` — add a pi agent to the extension with access to content and URLs (complete, delivered via the factory implementer pipeline)
- **survival-infrastructure**: think about extension, people profiles, audio event ingestion via whisper.cpp (pending); Gmail+GDrive instruction sources (queued)
- **workspace-portability**: set up themistocles, update with latest opensource projects, move everything to a cloud instance (pending)
- **headroom-pi**: work on it and run evals (pending)
- **resume**: personal website and blog with toTweet/toBlog/toVideo pipeline, website agent-first, GitHub profile fix (pending)
- **langfuse**: integrate official skill and operate Langfuse agentically (pending)

Recently completed: `extend-pm-assembly-line`, `x-capture-instrument` (UAT passed, PRD archived), `task-file-dashboard`, `combine-factory-context-factory-txt`, `chronological-tracking`, `extend-software-factory-wsff`, `end-to-end-traceability`, `vision-task-traceability`, `github-browser-auth-flow`, `feed-analyser-survival-infra-private-repos`, plus the software-factory pipeline tasks and headless-loop tasks: `implementer-agent`, `code-review-agent`, `implementer-ponytail`, `implementer-revision-mode`, `extension-inline-agent`, `ponytail-skills-fixed-mount`, `sandbox-credential-mounting`, `task-pickup-similarity-merge`, `headless-agent-containerisation`, and `implementer-delivery-failure-loud` (merged PRs #10/#11).

## Backlog

- **timesheetViewer/** — Spring Boot app for Excel timesheet validation. Deferred: standalone project, not part of the core LLM/data-pipeline ecosystem. See its [README](/timesheetViewer/README.md).
- **resume/** — Flask Markdown resume editor. Deferred: personal productivity tool, not part of the infrastructure ecosystem. See its [README](/resume/README.md).
- **emotional_architecture/** — Personal operating manual, code of conduct, and relationship templates. Deferred: personal documents, not code documentation. See [/emotional_architecture/functional/](/emotional_architecture/functional/).
- **Individual OSS contrib repos** — Deferred: documented as a list below; deep coverage deferred to their own repositories.

## Knowledge Base

A session-based knowledge base at [`/docs/knowledge/index.md`](/docs/knowledge/index.md) captures architectural decisions, tool evaluations, and session learnings via the `save-knowledge` skill, organised **by project**. Each entry is a structured decision record (`Context` / `Decision` / `Rationale` / `Consequences` / `Revision triggers`) linking to the full session `session.jsonl`. The OKF-compliant [Agent Configuration](/openwiki/reference/agent-config.md) page and [Software Factory](/openwiki/projects/software-factory.md) page point into it; it is the deliberate "last resort" layer in the factory's progressive-disclosure chain.

Representative decisions added since 2026-07-29:
- **software-factory**: [PRD as Routing Document + Review Sub-Agent Gate](/docs/knowledge/sessions/019fd00b-4e86-76ed-966b-186ea09c775c/decisions/01-prd-as-routing-document-context-engine-depth.md), [Subagent Infrastructure — Official Pi Extension, Project-Local, Read-Only Reviews](/docs/knowledge/sessions/019fd00b-4e86-76ed-966b-186ea09c775c/decisions/04-subagent-infrastructure-pi-extension-project-local.md), [Temporal Metadata Convention](/docs/knowledge/sessions/019fc389-c171-7c69-9eeb-6100abd6bc87/decisions/01-temporal-metadata-convention.md), [Reliable Lifecycle Transition Script with Test Suite](/docs/knowledge/sessions/019fbd12-7ea3-7152-9eec-f865cf69d6f7/decisions/03-reliable-transition-script-with-tests.md), [PRD status lifecycle — Final when the review gate passes](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/07-prd-status-lifecycle.md), [Ponytail skills via fixed `/skills` mount](/docs/knowledge/sessions/01a005a8-7302-74e2-8c1a-c6e8e74358c7/decisions/01-ponytail-skills-fixed-mount.md), [Task similarity merge policy](/docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/decisions/01-task-similarity-check-scope.md), [LLM credential resolution from pi's auth.json](/docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/decisions/04-llm-credential-resolution-from-auth-json.md), [GitHub Actions as fast-path backend](/docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/03-github-actions-fast-path.md), [`--headless` loop to APPROVE](/docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/04-factory-run-headless-loop.md), [CI tracking sync on ephemeral runners](/docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/07-ci-tracking-sync-ephemeral-runners.md), [Delivery failures must be loud](/docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/08-delivery-failure-loud.md), [Code reaches master only via PR merge](/docs/knowledge/sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/decisions/09-code-master-pr-gate.md), [The code-review agent never merges PRs](/docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/05-review-never-merges.md), [Cross-repo `--revise` needs a 36-char impl-session UUID](/docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/13-revise-cross-repo-uuid-join.md)
- **feed-analyser (capture)**: [PI SDK agent service](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/01-pi-sdk-agent-service.md), [Capture artefact is a recursive node tree](/docs/knowledge/sessions/019fd314-9339-7a30-9b8b-f6d8892b5226/decisions/04-capture-recursive-node-tree-comment-is-tweet.md), [Plain files as truth + SQLite FTS5 read API](/docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/05-twitter-kb-plain-files-fts5-read-api.md)
- **workspace-portability**: [GitHub Device Authorization Flow Implementation](/docs/knowledge/sessions/019faf44-901a-73f9-aa74-817eead12980/decisions/01-github-device-auth-flow-implementation.md), [Device Flow End-to-End Test Verification](/docs/knowledge/sessions/019faf44-901a-73f9-aa74-817eead12980/decisions/02-device-flow-test-verification.md)
- **langfuse-agentic-operations**: [Self-hosted Langfuse v3 → v4 Upgrade](/docs/knowledge/sessions/019fc40a-5458-7310-89c4-53e098060973/decisions/01-langfuse-v3-to-v4-upgrade.md)

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
