# Project Inventory & Task Mapping

> **Purpose:** Consolidated view of all projects in the workspace, their purpose, and which tasks they belong to.
> **Last updated:** 2026-07-21

---

## Overview

The workspace contains **10 first-party projects** (owned/developed by us) plus **16 open-source projects** (cloned/forked). This document maps each task from `tasks.txt` to the project it concerns, and tags infrastructure-level tasks separately.

---

## First-Party Projects

### 1. `llm` — LLM Inference Server & Shared Client

| Field | Value |
|-------|-------|
| **Description** | Llama.cpp-based inference server (Flask) with provider routing, managed server lifecycle, and the shared `llm_client` package consumed by other apps |
| **Remote** | `ak47-arch/llamacpp_inference_server.git` (branch: `pi_master`) |
| **Stack** | Python, Flask, llama.cpp, Docker/Podman |
| **Status** | ✅ Running — serves inference to survival-infrastructure & feed_analyser |

**Related tasks:**
- [ ] **common llm api** — the `llm_client` shared package migration is done, but known issues remain (see `KNOWN_ISSUES.md`)

---

### 2. `survival-infrastructure` — Personal Intelligence Pipeline

| Field | Value |
|-------|-------|
| **Description** | Pipeline that captures raw narrative events, extracts structured data via LLM, stores markdown-native people/event nodes, and synthesizes wiki pages |
| **Remote** | `ak47-arch/goal-agent.git` (branch: `pi_master`) |
| **Stack** | Python, Flask, SQLite, LLM integration via `llm_client` |
| **Status** | 🟡 Running — but `start_stack.sh` is broken (missing preflight script, see `KNOWN_ISSUES.md` #3) |

**Related tasks:**
- [ ] **think about survival infrastructure extension** — planning future capabilities

---

### 3. `feed_analyser` — Social Media Feed Analysis

| Field | Value |
|-------|-------|
| **Description** | Feed ingestion (Twitter), classification pipeline with LLM + heuristic fallback, frontend/backend/sandbox architecture |
| **Remote** | `forthechemicals/forthechemicals_agentic_social_media.git` (branch: `master`) |
| **Stack** | Python, Flask, React frontend, Docker/Podman |
| **Status** | ✅ Running — Twitter ingestion working |

**Related tasks:**
- [ ] **extend feed analyser with youtube, gmail and gdrive** — adding new data sources

---

### 4. `headroom-pi` — Compression Proxy & Health Monitor

| Field | Value |
|-------|-------|
| **Description** | Compression proxy for Pi agent (context window optimization), systemd integration, health monitoring |
| **Remote** | `ak47-arch/headroom-pi.git` (branch: `main`) |
| **Stack** | Go, systemd, proxy |
| **Status** | 🟡 In development — reliability issues, eval not yet run |

**Related tasks:**
- [ ] **work on headroom-pi and get that working reliably and run eval**

---

### 5. ~~`mission-control` — Pane Monitoring Dashboard~~

~~DEPRECATED — removed from workspace. See `docs/tasks.txt` for context.~~

| Field | Value |
|-------|-------|
| **Description** | ~~Rust workspace: schema, core collector, binary. Collected pane state from herdr and Pi signals. Provided TUI + web dashboard~~ |
| **Remote** | ~~[ak47-arch/mission-control.git](https://github.com/ak47-arch/mission-control.git)~~ |
| **Stack** | ~~Rust (mc-schema, mc-core, mc-binary)~~ |
| **Status** | ~~Deprecated — removed from workspace.~~ |

---

### 6. `workspace-portability` — Backup & Restore System

| Field | Value |
|-------|-------|
| **Description** | Three-tier backup/restore: full workspace restore, repo sync, data restore. Bootstraps new machines. |
| **Remote** | `ak47-arch/workspace-portability.git` (branch: `main`) |
| **Stack** | Python, shell scripts, rclone, GitHub Releases, GDrive |
| **Status** | ✅ Phase 1 complete & verified on themistocles. Phase 2 (setup-guide) built but not tested remotely. |

**Related tasks:**
- [ ] **implement github browser authentication flow for project restore** — authentication for restore on new machines
- [ ] **clean up the project root. move open source projects in a seperate directory and update workspace portability** — partially done (opensource/ dir exists, but needs verification)

---

### 7. `resume` — Resume Editor

| Field | Value |
|-------|-------|
| **Description** | Container-based resume editor/viewer application |
| **Remote** | `ak47-arch/resume.git` (branch: `main`) |
| **Stack** | (container app) |
| **Status** | 🟡 Needs assessment |

**Related tasks:**
- _(none directly in tasks.txt)_

---

### 8. `timesheetViewer` — Timesheet Validation

| Field | Value |
|-------|-------|
| **Description** | Java/Spring Boot timesheet validation app |
| **Remote** | `ak47-arch/timesheetViewer.git` |
| **Stack** | Java, Spring Boot, Maven |
| **Status** | 🟡 Phase 4 validation work was in progress, UI fixes needed |

**Related tasks:**
- _(none directly in tasks.txt)_

---

### 9. `emotional_architecture` — Personal Operating Manual

| Field | Value |
|-------|-------|
| **Description** | Code of conduct / personal operating manual |
| **Remote** | `ak47-arch/emotional_architecture.git` (branch: `master`) |
| **Stack** | Markdown documentation |
| **Status** | ✅ Static — reference material |

**Related tasks:**
- _(none directly in tasks.txt)_

---

### 10. `openwiki` — Documentation Wiki

| Field | Value |
|-------|-------|
| **Description** | Static documentation wiki — intended to be the hub for shared context across projects |
| **Remote** | Not a git repo directly; wiki content lives in `openwiki/` directory |
| **Stack** | Markdown, static site generator |
| **Status** | 🟡 In planning — `_plan.md` defines intended pages, many not yet written |

**Related tasks:**
- [ ] **build the shared context infrastructure with open wiki** — the primary goal for this project

---

## Infrastructure Tasks (Cross-Cutting)

These tasks don't belong to a single project — they span the whole workspace or are about the development environment itself.

| # | Task | Description |
|---|------|-------------|
| 2 | **modularising all apps** | Making apps independently deployable, cleaning up shared package patterns |
| 3 | **thorough testing** | Adding test coverage across all projects |
| 4 | **agent containerisation** | Containerizing agents for isolated deployment |
| 7 | **clean up the project root** | Move open-source projects into `opensource/`, update workspace-portability manifest |
| 8 | **build shared context infrastructure** | OpenWiki as the knowledge hub — also touches openwiki project |
| 9 | **set up langfuse** | Observability/tracing for LLM calls across all apps |
| 11 | **set up themistocles and run everything on that** | Move compute to second system (laptop hitting limits) |

---

## Open-Source Projects (in `opensource/`)

These are cloned/forked third-party projects. Not actively developed by us, but some are used as dependencies.

| Project | Remote | Notes |
|---------|--------|-------|
| `agent-browser` | `vercel-labs/agent-browser` | Browser automation |
| `Agent-Reach` | `Panniantong/Agent-Reach` | — |
| `anything-llm` | `Mintplex-Labs/anything-llm` | LLM UI |
| `graphify` | `safishamsi/graphify` | Code graph analysis |
| `headroom` | `chopratejas/headroom` | Context compression (upstream of headroom-pi) |
| `herdr` | `ak47-arch/herdr` | Terminal workspace manager (forked) |
| `hermes` | `ak47-arch/hermes` | Agent framework (forked, 7 custom commits) |
| `hunk` | `modem-dev/hunk` | — |
| `langfuse` | `langfuse/langfuse` | LLM observability (to be set up) |
| `open-notebook` | `lfnovo/open-notebook` | — |
| `openwiki` | `ak47-arch/openwiki` | Wiki generator (forked) |
| `pi-mono` | `ak47-arch/pi-mono` | Pi framework (removed from backup manifest) |
| `skills` | `ak47-arch/skills` | Shared skills collection |
| `Understand-Anything` | `Egonex-AI/Understand-Anything` | — |
| `woodpecker` | `woodpecker-ci/woodpecker` | CI system |
| `yazi` | `sxyazi/yazi` | Terminal file manager |

---

## Task Status Legend

```
[ ]  — Not started
[~]  — In progress
[x]  — Done
[!]  — Blocked
```

(Current `tasks.txt` has all items as unmarked — we'll evolve this as we track progress.)

---

## Next Steps

1. **Review and validate** this mapping — is every project accounted for? Are the task-project associations correct?
2. **Add per-project status** — for each first-party project, note what state it's in (running, broken, planning, etc.)
3. **Evolve `tasks.txt`** into a richer tracking format — perhaps a per-project section in this document, or a separate `docs/project-status.md`