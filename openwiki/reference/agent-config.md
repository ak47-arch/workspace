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
  "extensions": ["langfuse-tracing"],
  "enableSkillCommands": true
}
```

- Extensions list enables `langfuse-tracing` (the only extension enabled at startup)
- Skill commands are enabled

### Extensions (`/.pi/extensions/`)

| File | Purpose |
|------|---------|
| `question-suggestions.ts` | Suggests follow-up questions during agent sessions |
| `confirm-directory-delete.ts` | Asks for confirmation before deleting directories |
| `confirm-git-push.ts` | Asks for confirmation before git push operations |
| `database-write-guard.ts` | Guards against unintended database writes |
| `herdr-agent-state.ts` | Tracks agent state via herdr integration. Installed/managed by herdr (v6 integration); reinstalling herdr's integration overwrites this file, so local patches must be re-applied. A `2026-08-09` patch unrefs and clears the 10 s heartbeat interval so non-interactive pi children (subagents in `--mode json --no-session`) exit after `agent_settled` instead of hanging (see [Software Factory](/openwiki/projects/software-factory.md)). |
| `langfuse-tracing.ts` | Langfuse observability integration — captures every agent turn (LLM requests/responses, tool calls) and sends to self-hosted Langfuse as traces, generations, and spans. Requires `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_BASE_URL` env vars or `~/.pi/agent/langfuse-config.json`. Gracefully degrades if Langfuse is unreachable. |
| `subagent/` | Symlinked pi subagent extension (from `opensource/pi-mono/packages/coding-agent/examples/extensions/subagent/`) — agent discovery + config for factory sub-agents. See [Software Factory](/openwiki/projects/software-factory.md). |

### Sub-Agents (`/.pi/agents/`)

| File | Purpose |
|------|---------|
| `prd-reviewer.md` | Read-only PRD verification sub-agent that gates plan documents for implementation readiness. Runs deterministic + judgment checks and returns a blocking/advisory report. Uses model `deepseek/deepseek-v4-flash-0731`; tools are `read, grep, find, ls, bash` (no write tools at the mechanism level). Invoked with `agentScope: "project"` or `"both"`. See [Software Factory](/openwiki/projects/software-factory.md). |
| `implementer.md` | The autonomous implementation sub-agent (the "hands" of the implementer pipeline). System prompt embeds the ponytail lazy-senior-dev style (always-on) + factory-worker rules + the implementer-ops run contract. Model `openrouter/deepseek/deepseek-v4-flash-0731`; runs headless in the sandbox container (`pi --mode json --no-session -p`). See the [implementer PRD](https://github.com/ak47-arch/workspace/blob/master/docs/prd-queue/2026-08-10-implementer-agent.md). |
| `code-reviewer.md` | Read-only post-implementation review sub-agent (the sibling of the implementer). Reviews a factory-raised PR against its PRD inside the sandbox, runs deterministic + judgment checks (including the PRD's own verification commands and the ponytail over-engineering pass), and writes a structured APPROVE / REQUEST_CHANGES report to the outbox. Model `openrouter/deepseek/deepseek-v4-flash-0731`; tools are `read, grep, find, ls, bash`. Never mutates the repo and never runs `gh` — the host driver owns all git mutations, gh calls, labels, comment posting, and lifecycle transitions. Runs headless via `bin/review-run.sh`. See [Software Factory](/openwiki/projects/software-factory.md). |

### Skills (`/.pi/skills/`)

The `.pi/skills/` directory is currently empty — the `improve-codebase-architecture` and `workspace-backup-recovery` skills referenced here in earlier revisions have been deleted. Operational skills now live under `.agents/skills/` (below).

(The `agent-browser`, `codebase-design`, and `karpathy-guidelines` skills were likewise deleted in recent commits.)

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

### implementer-ops (`/.agents/skills/implementer-ops/SKILL.md`)

The run contract for the autonomous implementer agent (headless, inside the sandbox).

- Read the brief (`/sandbox/brief.md`), iterate story-by-story inside the worktree (no git — the host authors the commit; a respawn continues the same pi session)
- Run the PRD verification commands; record what could not be verified for UAT
- Produce the outbox contract: `report.md` (per-story done/not-done + evidence) + `decisions/NN-<slug>.md`
- Hard rules: modify only the worktree, no secrets, no git commands, no push/PR (driver-owned), no index edits

**Usage:** loaded automatically by the implementer agent in the sandbox container.

### implementer-save (`/.agents/skills/implementer-save/SKILL.md`)

Scoped decision capture for the headless implementer. The `save-knowledge` session-finding heuristic is blind headless, so this skill takes the session directory explicitly from the brief and writes decisions to the outbox (`/sandbox/outbox/decisions/NN-<slug>.md`). The **driver** appends the `docs/knowledge/index.md` entry deterministically via `bin/sort-knowledge-index.py` — the model never touches the index.

### review-ops (`/.agents/skills/review-ops/SKILL.md`)

The run contract for the autonomous code-reviewer agent (headless, inside the sandbox). Defines the exact review protocol: orient on the PR + PRD, diff `base...head` read-only, run the PRD verification commands, run the deterministic + judgment check classes (including the ponytail over-engineering pass), and assemble the fixed-schema outbox report with an APPROVE / REQUEST_CHANGES verdict.

- Hard rules: the worker may run read-only git (`diff/log/show/status`) but never mutates git state, never runs `gh`, and holds no GitHub credential — all mutations + PR comments are driver-side.
- Add robustness checks here (a skill edit), never in the host driver.

**Usage:** loaded automatically by the code-reviewer agent in the sandbox container, invoked via `bin/review-run.sh`.

### vscode-git-viewer-fix (`/.agents/skills/vscode-git-viewer-fix/SKILL.md`)

Operational workaround skill for a local VSCode extension. See the SKILL.md for the specific fix steps.

### workspace-backup (`/.agents/skills/workspace-backup/SKILL.md`)

Backup/restore operational skill for the workspace. Complements the [workspace-portability](/openwiki/operations/infrastructure.md) tooling.

### product-layer (`/.agents/skills/product-layer/SKILL.md`)

Start a product/architecture session. Produces plan documents and structured design decisions. Operates the product/architecture layer of the [software factory](/openwiki/projects/software-factory.md) — the UX layer the user interacts with directly.

- Reads `docs/factory-context.md` for the factory model, `docs/tasks.txt` for task selection
- Grilling process using technique guides from `opensource/skills/docs/engineering/`
- Produces the plan document: PRD/design (saved to `docs/prd-queue/`, archived to `docs/prd-archive/` on completion) and design decisions (saved to `docs/knowledge/sessions/<uuid>/decisions/`)
- During grilling, categorises the task (Trivial/Small/Medium/Large), derives a slug, creates the task file `docs/tasks/<slug>.md`, and annotates `docs/tasks.txt` with `[<slug>]`
- Uses `save-knowledge` skill for decision capture and `bin/transition-task.sh` for lifecycle bookkeeping
- `disable-model-invocation: true` — user-invoked only

**Usage:** When starting a new product/architecture task that needs a plan document and decision record.

## Planning & Tasks

### tasks.txt

High-level task list from `/docs/tasks.txt`. Tasks are organised **by project, then by status** (Pending / Queued / Complete), and each line may carry a `[<slug>]` annotation linking to its task file. See [Software Factory](/openwiki/projects/software-factory.md) for the lifecycle.

Current highlights (as of 2026-08-09):
- **software-factory**: thinking about automated monitoring, cognee evaluation, task-selection abstraction layer, extends the prod review agent, headless herdr host, no-prompt-before-delete infrastructure, build the factory into its own product with evals, host apps in test/main/prod environments, save compressed sessions on disc (all pending)
- **software-factory** completed: end-to-end traceability, vision-task-traceability, extend-software-factory-wsff, task-file-dashboard, combine-factory-context-factory-txt, chronological-tracking, extend-pm-assembly-line, x-capture-instrument, implementer-agent, code-review-agent, implementer-ponytail, implementer-revision-mode
- **workspace-portability**: GitHub browser auth flow, make private repos both complete; cloud migration + themistocles setup pending
- **langfuse**: langfuse-agentic-operations (integrate official skill, operate agentically) pending
- **resume**: personal website/blog/toTweet-toBlog-toVideo pipeline, website agent-first, GitHub profile fix (all pending)
- **survival-infrastructure**: extension, people profiles, whisper.cpp audio ingestion pending; Gmail+GDrive queued

### PLAN_shared_llm_client.md

Architecture plan that drove the `llm_client` migration. Key decisions:

- Extract a single shared `llm_client` package from three consuming codebases
- Per-project `config/workflows.yaml` for model definitions and workflow parameters
- Server stays a dumb OpenAI-compatible pipe; all intelligence in the client

### KNOWN_ISSUES.md

Reorganized as a factory-context / post-migration debt tracker. Current entries:

| Issue | Severity | Status |
|-------|----------|--------|
| 1. `llm_client` served via PYTHONPATH mount | Medium | Open |
| 2. `llm` repo `pi_master` branch not pushed | High | ✅ Resolved |
| 3. `start_stack.sh` references missing preflight script | High | Open |
| 4. Reasoning parameters locked in server flags | Medium | Open |
| 5. Resume project missing vision doc | Low | Open |
| 6. Subagent tool description is largest single context item | Low | Open |
| 7. Knowledge base storage is file-based, may not scale | Low | Open |

### HEADROOM-PI-PLAN.md

Implementation summary for headroom-pi integration, documenting:

- 7 files created (systemd units, health check, shell wrapper, models.json, bash alias)
- Architecture diagram showing pi → headroom-pi → Headroom proxy → OpenRouter
- Deployment verified as done (2026-06-20 to 2026-06-21)

## Git History Notes

Recent commits (2026-07-29 → 2026-08-09) added the software-factory assembly line, capture instrument, and subagent infrastructure:

| Commit | Change |
|--------|--------|
| `5bd33ec` | herdr-agent-state.ts: unref+clear heartbeat interval so pi children exit after `agent_settled` (fixes subagent handover hang) |
| `36fd9bd` | extension-inline-agent task: PRD-ready with decisions (pi SDK agent service, OpenRouter server-side key, fetch-url-only tools, artefact/session evidence, FTS5 knowledge base, browser control deferred) |
| `f0cf8a6` | extended software factory: installed pi subagent extension + project-local `prd-reviewer` sub-agent |
| `f11aed1` | registered subagent infrastructure decision (04) in knowledge base |
| `b689ea9` | marked reviewed/completed PRDs Final (github-browser-auth, x-capture, wsff, task-file-dashboard) |
| `d91631a` | captured PRD status lifecycle, subagent/herdr hang root cause, and chunked-writing decisions |
| `a209f15` | factory temporal metadata convention — backfill script, index sort, template updates |
| `be057a2` | merged factory.txt into factory-context.md; renamed `knowledge_base` → `context_engine` |
| `daa5ed8` / `a89df51` | added `bin/transition-task.sh` for lifecycle bookkeeping, then made it reliable with a test suite (`bin/test-transition-task.sh`) |
| `d156ea9` | archived x-capture-instrument PRD; marked the task complete after UAT + user go-ahead |


## Source Files Summary

| Path | Purpose |
|------|---------|
| `/AGENTS.md` | OpenWiki reference + software factory pointer for coding agents |
| `/CLAUDE.md` | OpenWiki reference for coding agents (same content) |
| `/.pi/settings.json` | Pi agent settings (enables `langfuse-tracing`) |
| `/.pi/extensions/` | Pi extensions directory (including `subagent/`) |
| `/.pi/agents/` | Project-local sub-agent definitions (`prd-reviewer.md`, `implementer.md`) |
| `/.pi/skills/` | Pi skills directory |
| `/.agents/skills/` | Agent skills directory (`implementer-ops`, `implementer-save` are implementer-pipeline skills) |
| `/bin/implementer-run.sh` | Implementer host driver (pick → worktree → container → report → PR) |
| `/bin/sandbox-build.sh`, `/config/implementer.json` | Sandbox image build + driver config |
| `/docs/tasks.txt` | High-level task list (by project + status) |
| `/docs/tasks/<slug>.md` | Per-task reference hubs |
| `/docs/prd-queue/` | Forward-looking plan documents for active tasks |
| `/docs/prd-archive/` | Completed plan documents |
| `/docs/factory-context.md` | Software factory model + link index |
| `/docs/knowledge/index.md` | Curated decision records (by project) |
| `/llm/PLAN_shared_llm_client.md` | LLM client migration plan |
| `/docs/KNOWN_ISSUES.md` | Factory/post-migration technical debt |
| `/headroom-pi/HEADROOM-PI-PLAN.md` | Headroom integration plan |
| `/bin/transition-task.sh` | Lifecycle bookkeeping script |
| `/bin/test-transition-task.sh` | transition-task test suite |
| `/package.json` | Workspace package metadata ("workspace-omp-local-tools") |