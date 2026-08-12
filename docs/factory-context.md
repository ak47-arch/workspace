# Factory Context

This is where everything is. If you need anything just follow the trail.

## Software Factory

This workspace is developed and maintained under a **software factory** paradigm.
Four components, one rule: the user only interacts with the product/architecture
layer — everything else is automation.

**context_engine** — Infrastructure spine. Every other component reads/writes it.
Progressive disclosure keeps agents lean: context loads on demand, never pre-loaded.
Agents follow the chain downward and stop when they have enough. The knowledge base
(`docs/knowledge/` — curated design decisions) is the last stop — consulted only
when code, docs, and vision don't answer the question.

**product/architecture** — UX layer. The only surface the user interacts with.
Produces one artifact per task: a single plan document that accumulates Product
Design, System Architecture, and Program Design sections based on task size.
Invoked via the `product-layer` skill.

**project_management** — Prioritisation and lifecycle tracking. Task dashboard
(remote), task files (`docs/tasks/<slug>.md`), lifecycle state machine
(`in-prd` → `prd-ready` → `in-progress` → `in-review` → `complete`).
Tooling: `bin/transition-task.sh`.

**PRD lifecycle.** A PRD enters `docs/prd-queue/` when its task reaches
`prd-ready`, and it leaves the queue (moves to `docs/prd-archive/`) only when
its task is genuinely done. "Done" means the feature passed user acceptance
testing **and** the user explicitly gave the go-ahead — **code written + unit
tests passing is NOT "complete."** Until UAT passes and the user signs off,
keep the task at `prd-ready` and the PRD in the queue. To reopen an archived
PRD: move it back to `docs/prd-queue/`, set the task to `prd-ready`, and
re-point the Plan artifact path. (See decision
[PRD moves to archive only after UAT + user go-ahead](knowledge/index.md).)

**assembly_line** — CI/CD, agents, sandboxes, testing. Built YAGNI — least
developed component. Its first real component is the **implementer agent**: a
decoupled brain/hands pipeline (`bin/implementer-run.sh` host driver + a
disposable sandbox container) that picks a `Final` PRD from `docs/prd-queue/`,
implements it in a durable host-side worktree via a headless `pi` worker, and
raises a PR — the user only inspects/accepts the result. Durable stores:
`~/.factory/runs/<slug>-<ts>/` (per-run) and `docs/implementations/`
(archived reports + decisions).

> **Where everything lives**: every build/runtime/config/persona artefact is
> mapped in [`docs/reference/implementer-agent.md`](reference/implementer-agent.md) —
> consult it to resolve any implementer artefact in one hop rather than grepping.

## Agents (the workforce)

Agents are the factory's employees — each staffs a stage of the SDLC. The
roster grows as stages are staffed; a task that needs an unlisted role means a
new agent file in `.pi/agents/<name>.md` (and a subagent/tool invocation that
calls it). The roster lives here so the workforce is discoverable in one hop,
never buried in grep results.

| Agent (employee) | SDLC stage | Role | Where it lives / how it's run |
|---|---|---|---|
| **prd-reviewer** | PRD gating (before implementation) | Read-only readiness verifier — gates a plan doc with deterministic + non-deterministic checks, returns a blocking/advisory report | `.pi/agents/prd-reviewer.md` · invoked with `agentScope` project/both |
| **implementer** | Implementation (build → PR) | Headless worker (the "hands") — implements a `Final` PRD inside the sandbox worktree, writes report + decisions to the outbox; host raises the PR | `.pi/agents/implementer.md` · run via `bin/implementer-run.sh` (full loop = driver + container image `sandbox:latest`) |

## Progressive Disclosure

The agent discovers context on demand. It never loads everything at once.

```
AGENTS.md
  "Code is truth. For full inventory, see factory-context.md.
   Knowledge base is the last resort."
    │
    ▼
factory-context.md (this file)
  Factory model, project inventory, vision doc pointers, link index.
    │
    ▼
Discovery layer
  openwiki/           Per-project code docs (what/how)
  docs/vision/        Stakeholder vision, end goals (why a project exists)
  docs/prd-queue/     Forward-looking specs for active tasks
  .agents/skills/     Operational playbooks
    │
    ▼ (last resort)
Knowledge base
  docs/knowledge/index.md  →  decisions  →  session.jsonl (full context)
```

Initial context footprint: ~2,500 tokens (system prompt + AGENTS.md + skills +
subagent tool description).

The knowledge base is the deepest and most expensive layer. It's deliberately
the last stop — agents only drill into it when code and OpenWiki can't explain
why something was built a certain way. Each entry is a structured decision
record with a link to the raw session trace for full reconstruction.

## Projects

Each first-party project has its own `openwiki/` for project-specific documentation.

| Project | Status | Docs |
|---------|--------|------|
| `llm/` | Inference server. ✅ Running | [openwiki](openwiki/projects/llm-server-client.md) |
| `survival-infrastructure/` | Personal intelligence pipeline. 🟡 Broken preflight | [openwiki](openwiki/projects/survival-infrastructure.md) |
| `feed_analyser/` | Capture instrument: thin Chrome extension + minimal local server. Legacy version archived. | [archive/openwiki](https://github.com/ak47-arch/feed_analyser/tree/main/archive/openwiki) (legacy) |
| `headroom-pi/` | Compression proxy for pi. 🟡 Needs eval | project's own `openwiki/` |
| `workspace-portability/` | Backup/restore/bootstrap. ✅ Phase 1 done | project's own `openwiki/` |
| `resume/` | Resume editor. Deferred — not actively developed | project's own `openwiki/` |
| `emotional_architecture/` | Personal operating manual. Static | — |
| `timesheetViewer/` | Timesheet validation. Deferred | — |

## Vision / Design Intent

When you need to understand **why** something was built or why it works a
particular way, consult each project's vision or design doc.

**Convention**: [docs/vision-convention.md](vision-convention.md)

| Project | Vision Doc | Status |
|---------|-----------|--------|
| `survival-infrastructure/` | [`docs/technical/VISION.md`](../survival-infrastructure/docs/technical/VISION.md) — stakeholder vision | ✅ Written |
| `survival-infrastructure/` | [`docs/technical/TECHNICAL_VISION.md`](../survival-infrastructure/docs/technical/TECHNICAL_VISION.md) — technical roadmap | ✅ Written |
| `feed_analyser/capture/` | [`docs/vision/VISION.md`](../feed_analyser/capture/docs/vision/VISION.md) — capture instrument vision | ✅ Written |
| `llm/` | [`docs/vision/VISION.md`](../llm/docs/vision/VISION.md) — inference server & client vision | ✅ Written |
| `headroom-pi/` | [`docs/vision/VISION.md`](../headroom-pi/docs/vision/VISION.md) — compression proxy vision | ✅ Written |
| `workspace-portability/` | [`docs/vision/VISION.md`](../workspace-portability/docs/vision/VISION.md) — portability system vision | ✅ Written |
| `resume/` | — | ❌ Missing (deferred) |

These give you the bigger picture of what each project is about and where it's
headed. Read the relevant one when you need context about purpose or direction
before making changes.

## Temporal Metadata

Every artifact in the factory carries a timestamp with **minute precision**
so agents can reconstruct chronological order with a single `rg` call — no
sequence numbers, no counters, no coordination.

### Convention

| Artifact | Field | Format | Example |
|----------|-------|--------|--------|
| Decision files (`docs/knowledge/sessions/*/decisions/*.md`) | `**Date**:` | `yyyy-mm-dd HH:MM` | `**Date**: 2026-07-30 14:23` |
| Task files (`docs/tasks/<slug>.md`) | `**Created**:` | `yyyy-mm-dd HH:MM` | `**Created**: 2026-07-30 14:23` |

### Knowledge base index

Within the index (`docs/knowledge/index.md`), entries are sorted **oldest → newest**
within each project section, so a scan down the section reads as an evolution
timeline.

### Token-efficient search

Agent can query the full timeline without parsing dates or UUIDs:

```bash
# All decisions, chronologically
rg "^\\*\\*(Date|Created)\\*\\*" docs/knowledge/sessions/*/decisions/*.md | sort

# All task files, chronologically
rg "^\\*\\*Created\\*\\*" docs/tasks/*.md | sort

# Cross-project: all decisions AND tasks sorted together (full factory timeline)
rg "^\\*\\*(Date|Created)\\*\\*" docs/knowledge/sessions/*/decisions/*.md docs/tasks/*.md | sort

# Per-project: sequence of decisions and tasks for one project, single command
rg "^\\*\\*(Date|Created|Project)\\*\\*" docs/knowledge/sessions/*/decisions/*.md docs/tasks/*.md \
  | paste - - - | sort | grep "<project-slug>" | tr '\t' '\n'
```

The per-project command grabs the `Date`/`Created`/`Project` lines together,
sorts them, filters to one project's slug, and restores each triple to its
own line — giving the chronological sequence of tasks and decisions for that
project in a single `rg` call.

## Pointers

- [Tasks → docs/tasks.txt](tasks.txt)
- [Implementer Agent artefact map → docs/reference/implementer-agent.md](reference/implementer-agent.md)
- [Known Issues → docs/KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [Knowledge Base → docs/knowledge/index.md](knowledge/index.md)
- [Architecture → openwiki/architecture/overview.md](../openwiki/architecture/overview.md)
- [Operations → openwiki/operations/infrastructure.md](../openwiki/operations/infrastructure.md)
- [Agent Config → openwiki/reference/agent-config.md](../openwiki/reference/agent-config.md)
- [Quickstart → openwiki/quickstart.md](../openwiki/quickstart.md)
