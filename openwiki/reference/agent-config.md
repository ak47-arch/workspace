---
type: Reference
title: Agent Configuration and Skills
description: Root-level agent configuration files, skills, extensions, tasks, and known issues for the workspace.
tags: [reference, agent, skills, config, claude]
resource: /
---

# Agent Configuration & Skills

This page documents the root-level agent configuration, skills, and planning documents that govern how agents interact with the workspace.

## Agent Instructions

### AGENTS.md / CLAUDE.md

Both files contain an identical OpenWiki reference block:

```markdown
<!-- OPENWIKI:START -->

## OpenWiki

This repository uses OpenWiki for recurring code documentation. Start with
`openwiki/quickstart.md`, then follow its links to architecture, workflows,
domain concepts, operations, integrations, testing guidance, and source maps.

The scheduled OpenWiki GitHub Actions workflow refreshes the repository wiki.
Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer
updating source code/docs and letting OpenWiki regenerate.

<!-- OPENWIKI:END -->
```

These are agent-facing instruction files that direct coding agents to use the OpenWiki documentation as their primary reference.

## Pi Agent Configuration

**Source:** `/.pi/`

### Settings (`/.pi/settings.json`)

```json
{
  "extensions": [],
  "enableSkillCommands": true
}
```

- Extensions list is currently empty (previous extensions removed in recent commits)
- Skill commands are enabled

### Extensions (`/.pi/extensions/`)

| File | Purpose |
|------|---------|
| `question-suggestions.ts` | Suggests follow-up questions during agent sessions |
| `confirm-directory-delete.ts` | Asks for confirmation before deleting directories |
| `confirm-git-push.ts` | Asks for confirmation before git push operations |
| `database-write-guard.ts` | Guards against unintended database writes |
| `herdr-agent-state.ts` | Tracks agent state via herdr integration |
| `langfuse-tracing.ts` | Langfuse observability integration |

### Skills (`/.pi/skills/`)

| Directory | Description |
|-----------|-------------|
| `improve-codebase-architecture/` | Skills for improving codebase architecture |
| `workspace-backup-recovery/` | Skills for workspace backup and recovery |

(The `agent-browser`, `codebase-design`, and `karpathy-guidelines` skills were deleted in recent commits.)

## Agent Skills

**Source:** `/.agents/skills/`

### ssh-themistocles (`/.agents/skills/ssh-themistocles/SKILL.md`)

SSH connection skill for the secondary Debian system at `192.168.0.122`.

- User: `anupam` at host `themistocles-lan` (hostname `themistocles`)
- Passwordless SSH via `~/.ssh/id_ed25519`
- Commands survive SSH disconnections via persistent tmux session
- Covers 14 tracked repositories in the workspace

**Usage:** When asked to connect to "the second system" or "the Debian host," use this skill's tmux-based resilient command pattern.

### survival-infrastructure-operation (`/.agents/skills/survival-infrastructure-operation/SKILL.md`)

Complete operations guide for the [survival-infrastructure](/openwiki/projects/survival-infrastructure.md) pipeline.

- All operations go through the `Makefile`
- Provides quick reference table for `make start`, `make stop`, `make ps`, `make logs`, `make shell`, `make verify`, `make run`
- Documents make variables: `TARGETS`, `CONTAINER_RUNTIME`, `LLAMA_CPP_DIR`

**Usage:** When asked to start/stop/rebuild/debug the survival-infrastructure stack, reference this skill.

### save-knowledge (`/.agents/skills/save-knowledge/SKILL.md`)

Captures the current session's key decisions, architectural rationale, issues, or learnings into the knowledge base at `/docs/knowledge/`.

- Finds the active pi session via `ls -t ~/.pi/agent/sessions/--*--/*.jsonl | head -1`
- Infers a title and topic from the conversation
- Summarises into a freeform markdown file with date prefix
- Copies the full session JSONL alongside the summary
- Appends an index link to `/docs/knowledge/index.md`
- Idempotent: re-running on the same session UUID overwrites the existing entry

**Usage:** When the user wants to preserve session learnings, design decisions, or tool evaluations for future reference. The skill creates a durable, searchable knowledge entry with full context.

## Planning & Tasks

### tasks.txt

High-level task list from `/docs/tasks.txt`:

1. **Common LLM API** — Completed via `llm_client` migration
2. **Modularising all apps** — Extract independent concerns into reusable packages
3. **Thorough testing** — Expand test coverage across all projects
4. **Agent containerisation** — Containerise coding agent workflows
5. **Think about survival infrastructure extension** — Extend pipeline stages
6. **Extend feed analyser with YouTube, Gmail, GDrive** — Add new ingestion sources
7. **Clean up the project root** — Move open-source projects to `opensource/` directory and update workspace-portability — ✅ **Done**
8. **Build the shared context infrastructure with OpenWiki** — In progress
9. **Set up langfuse** — Observability/tracing platform
10. **Implement GitHub browser authentication flow** — For project restore
11. **Set up themistocles (secondary Debian host)** — Offload compute from laptop
12. **Work on headroom-pi** — Get it working reliably and run eval
13. **Create save-knowledge skill** — Summarise session learnings and attach context window link — ✅ **Done**

### PLAN_shared_llm_client.md

Architecture plan that drove the `llm_client` migration. Key decisions:

- Extract a single shared `llm_client` package from three consuming codebases
- Per-project `config/workflows.yaml` for model definitions and workflow parameters
- Server stays a dumb OpenAI-compatible pipe; all intelligence in the client

### KNOWN_ISSUES.md

Post-migration technical debt tracker (4 issues):

| Issue | Severity | Status |
|-------|----------|--------|
| 1. `llm_client` served via PYTHONPATH mount | Medium | Open |
| 2. `llm` repo `pi_master` branch not pushed | High | ✅ Resolved |
| 3. `start_stack.sh` references missing preflight script | High | Open |
| 4. Reasoning parameters locked in server flags | Medium | Open |

### HEADROOM-PI-PLAN.md

Implementation summary for headroom-pi integration, documenting:

- 7 files created (systemd units, health check, shell wrapper, models.json, bash alias)
- Architecture diagram showing pi → headroom-pi → Headroom proxy → OpenRouter
- Deployment verified as done (2026-06-20 to 2026-06-21)

## Git History Notes

Recent commits cleaned up several legacy files:

| Commit | Change |
|--------|--------|
| `4cd2828` | Deleted `.omp/` extension files (confirm-directory-delete, confirm-git-push, lsp-tools) |
| `33fe99f` | Deleted `.pi-session-pane-map.json`, `HERMES_DEBUGGING_LOG.md`, `PODMAN_MIGRATION_PLAN.md` |
| `f24c742` | Deleted `SKILLS_CONSOLIDATION_AND_QUALITY_REPORT.md` |
| `dffb84c` | Added Mission Control PRD and session-pane mapping |
| `cb4fc47` | Added pi skills (agent-browser, codebase-design, backup-recovery, tdd, karpathy-guidelines) — most later deleted |
| `87fecaf` | Added survival-infrastructure-operation skill |
| `336c496` | Added PLAN_shared_llm_client.md |
| `a505bd1` | Added KNOWN_ISSUES.md |
| `b784caf` | ssh-themistocles: repo count 13→14, restore tier separation |

## Source Files Summary

| Path | Purpose |
|------|---------|
| `/AGENTS.md` | OpenWiki reference for coding agents |
| `/CLAUDE.md` | OpenWiki reference for coding agents (same content) |
| `/.pi/settings.json` | Pi agent settings |
| `/.pi/extensions/` | Pi extensions directory |
| `/.pi/skills/` | Pi skills directory |
| `/.agents/skills/` | Agent skills directory |
| `/docs/tasks.txt` | High-level task list |
| `/llm/PLAN_shared_llm_client.md` | LLM client migration plan |
| `/docs/KNOWN_ISSUES.md` | Post-migration technical debt |
| `/headroom-pi/HEADROOM-PI-PLAN.md` | Headroom integration plan |
| `/package.json` | Workspace package metadata ("workspace-omp-local-tools") |