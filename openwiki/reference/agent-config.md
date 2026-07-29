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
| `langfuse-tracing.ts` | Langfuse observability integration — captures every agent turn (LLM requests/responses, tool calls) and sends to self-hosted Langfuse as traces, generations, and spans. Requires `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_BASE_URL` env vars or `~/.pi/agent/langfuse-config.json`. Gracefully degrades if Langfuse is unreachable. |

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

### manifest-add-repo (`/.agents/skills/manifest-add-repo/SKILL.md`)

Scans `opensource/` for git repos and adds any that exist on disk but are missing from the workspace restore manifest (`workspace-portability/workspace_restore_manifest.json`). Use when new repos have been cloned under `opensource/` and need to be registered for backup/restore operations.

- Deterministic Python script: `.agents/skills/manifest-add-repo/add-repo.py`
- Reads manifest, scans `opensource/` for `.git` directories, extracts git metadata (branch, primary remote, extra remotes)
- Appends missing repos to `additional_repos` section, sorted alphabetically by path
- No arguments needed — auto-discovers missing repos

**Usage:** Run after cloning a new repo under `opensource/` to register it for backup/restore.

### transcribe (`/.agents/skills/transcribe/SKILL.md`)

Local speech-to-text transcription using whisper.cpp. Supports WAV, MP3, FLAC, OGG, and any ffmpeg-compatible format. Also supports live microphone recording with automatic transcription and sending to pi as a prompt.

- Whisper.cpp build at `opensource/whisper.cpp/` with model `ggml-small.bin` (487 MB)
- `transcribe.sh <audio-file>` — transcribes audio file to stdout
- `speak-to-pi.sh` — records 5s from microphone, transcribes, sends to pi as prompt
- Triggered via `Ctrl+Super+V` hotkey (xbindkeys)

**Usage:** When the user wants to transcribe audio files, speak to pi, or use voice input.

### product-layer (`/.agents/skills/product-layer/SKILL.md`)

Start a product/architecture session. Produces PRDs and structured design decisions. Operates the product/architecture layer of the software factory — the UX layer the user interacts with directly.

- Reads `docs/factory.txt` for factory model, `docs/tasks.txt` for task selection
- Grilling process using technique guides from `opensource/skills/docs/engineering/`
- Produces two artifacts: PRD (saved to `docs/prd-queue/`) and design decisions (saved to `docs/knowledge/sessions/<uuid>/decisions/`)
- Uses `save-knowledge` skill for decision capture
- `disable-model-invocation: true` — user-invoked only

**Usage:** When starting a new product/architecture task that needs a PRD and decision record.

## Planning & Tasks

### tasks.txt

High-level task list from `/docs/tasks.txt`:

1. **Common LLM API** — Completed via `llm_client` migration
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
17. **Extend survival-infrastructure with Gmail and GDrive** — New instruction sources
18. **Deprecate spec-driven process** — For all projects
19. **Evaluate opensource/cognee integration** — Assess benefits for ecosystem
20. **Improve shared context infrastructure** — Add architecture design step
21. **Define projects clearly** — For efficient context infrastructure
22. **Make feed_analyser and survival_infrastructure private repos** — With current opensource repos
23. **Create personal website and blog** — Add toTweet, toBlog, toVideo pipeline (resume)
24. **Set up Langfuse agentically** — Use and operate Langfuse via agents

Completed tasks:
- Add script to update workspace_portability with latest opensource repos
- Create save-knowledge skill — Summarise session learnings and attach context window link
- Clean up project root — Move open source projects to separate directory
- Set up Langfuse — Fix langfuse-tracing.ts extension

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

Recent commits cleaned up several legacy files and added new skills:

| Commit | Change |
|--------|--------|
| `e7eff7e` | Fixed manifest-add-repo skill: added missing YAML frontmatter with name and description |
| `a81f00c` | Rewrote manifest-add-repo skill to auto-scan opensource/ and add missing repos |
| `51c86ec` | Added voice-to-pi via whisper.cpp + transcribe skill |
| `3d0dff0` | Added manifest-add-repo skill for registering new opensource repos |
| `7149dda` | Added disable-model-invocation to all skills except web-search and save-knowledge |
| `8112c52` | Added opensource repos — bitchat, bitchat-android, deepagents |
| `aea743f` | GDrive instruction source ingest — PRD and design decisions |
| `1ad1ffa` | PRD + knowledge: x-capture instrument design decisions |
| `b62305d` | Parallel repo clone decision |
| `e34cfcd` | Product-layer skill updates |
| `dbb8380` | Added vscode-git-viewer-fix skill |
| `23a2d9d` | PRD: GitHub browser auth flow |
| `66b39df` | Product-layer skill, structured knowledge capture, factory architecture decisions |
| `5b9f00f` | Software factory paradigm, knowledge base deep-dive, vision doc pointers |
| `1768101` | Fixed langfuse-tracing extension no longer blocks TUI when langfuse is down |
| `16d4a12` | Factory context index for progressive disclosure |
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