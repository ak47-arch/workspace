# Factory Context

This is where everything is. If you need anything just follow the trail.

## Software Factory

This workspace is developed and maintained under a **software factory** paradigm.
Five components, one rule: the user only interacts with the product/architecture
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
`prd-ready`, and leaves for `docs/prd-archive/` only when the task is genuinely
done: feature passed user acceptance testing **and** the user explicitly gave
the go-ahead — **code written + unit tests passing is NOT "complete."** Until
UAT + sign-off, keep the task at `prd-ready` and the PRD in the queue. To reopen
an archived PRD: move back to `docs/prd-queue/`, set the task to `prd-ready`,
re-point the Plan artifact path. (See decision
[PRD moves to archive only after UAT + user go-ahead](knowledge/index.md).)

**assembly_line** — CI/CD, agents, sandboxes, testing. Orchestrated by
`bin/factory-run.sh` (headless loop + per-task orchestration) and staffed by
two agents:
- **implementer agent** — a decoupled brain/hands pipeline
  (`bin/implementer-run.sh` host driver + a disposable sandbox container) that
  picks a `Final` PRD from `docs/prd-queue/`, implements it in a durable
  host-side worktree via a headless `pi` worker, and **raises one code PR per
touched repo + a bookkeeping PR to the workspace root** (multi-repo delivery,
  decision 01: Shape A = N app code PRs + 1 bookkeeping PR; Shape B = 1 root
  PR carrying code + bookkeeping commits). The user only UAT-inspects/merges.
- **code-reviewer agent** — a sibling pipeline (`bin/review-run.sh` host driver
  + a read-only `pi` worker) that picks up a raised PR, checks it against its
  PRD (deterministic + judgment checks incl. the PRD's verification commands
  and a ponytail over-engineering pass) and returns a structured APPROVE /
  REQUEST_CHANGES report posted to the PR — it never merges or completes a task.

**evaluation** — Continuous quality verification. Cross-cutting, read-only: runs
eval panels over the factory's own loops using the eval spine
(session/trace → artifact → gold check → Langfuse panel). Emits
`docs/evaluations/<date>-*.{json,md}` reports + Langfuse scores, never mutates
a target repo. Staffed by the **evaluator agent** (`.pi/agents/evaluator.md`
persona, run contract `.agents/skills/eval-ops/SKILL.md`). Artifact map:
`docs/reference/evaluator-agent.md`. Report home + index: `docs/evaluations/`.

Live surfaces (register: `docs/evaluations/surfaces.md`): **S1 decision-record
loop** · **S2 task loop (state-machine)** · **S3 knowledge loop** · **S4
PRD/review loop** · **S5 drift/L2 (fixes hold)** · **S7 context-engine
(footprint + reachability + fidelity)** · **S8 roster-completeness** · **S9
repo-hygiene**. S10 (app family) deferred until app preflights clear.

**Execution substrate**: local-first via herdr (dedicated worktree branch +
pane, sandbox container as containment, host driver owns git; GitHub stays the
repo/PR/evidence layer) — decision 03. GitHub Actions remains a trigger/
fallback. **Master is never pushed directly**: every default branch is
merge-only (branch protection, decision 02) and all content — including
bookkeeping — lands via reviewed PRs; `bin/merge-pr.sh` is the single operator
gate (user UAT → merge → Merge rows → task complete), now enforcing the **PR
dependency invariant** (decision 07: no undeclared ride-along commits, declared
`**Depends on:** #N` deps merge first). A pickup gate skips a task with an open
`factory/<slug>` PR.

**Evidence pipeline** (decision 05/06): durable per-run session logs are
filtered of the O(n²) `message_update` delta-replay (`bin/session-filter.sh`)
while keeping the complete message-level session for retrospective Langfuse
evals; run manifests + verdicts are written per run.

Durable stores: `~/.factory/runs/<slug>-<ts>/` (per-run) and
`docs/implementations/` (installer reports + decisions) +
`docs/code-reviews/` (review reports + decisions).

> **Where everything lives**: every build/runtime/config/persona artefact is
> mapped in [`docs/reference/implementer-agent.md`](reference/implementer-agent.md) and
> [`docs/reference/reviewer-agent.md`](reference/reviewer-agent.md) — consult them to
> resolve any implementer/reviewer artefact in one hop rather than grepping.

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
| **code-reviewer** | Post-implementation review (PR → report) | Read-only worker — checks a raised PR against its PRD (deterministic + judgment checks, runs the PRD's verification commands, ponytail over-engineering pass), writes an APPROVE/REQUEST_CHANGES report to the outbox; host posts it to the PR, labels, and transitions the task | `.pi/agents/code-reviewer.md` · `.agents/skills/review-ops/SKILL.md` · run via `bin/review-run.sh` (driver + image `sandbox:latest`; never merges/never completes) |
| **evaluator** | Continuous eval (production quality) | Read-only worker — runs eval panels over the factory's own loops (decision/task/knowledge/PRD-review/drift/context/hygiene) via the eval spine, writes PASS/SKIP/FAIL + evidence to a fixed-schema eval report (`docs/evaluations/<date>-*.{json,md}`), writes Langfuse scores; never mutates a target repo | `.pi/agents/evaluator.md` · `.agents/skills/eval-ops/SKILL.md` · run on demand via the eval brief (tooling: `bin/eval-decisions.py`, `bin/eval-pipeline.py`, `bin/eval-knowledge.py`, `bin/eval-prd.py`, `bin/eval-drift.py`, `bin/eval-context.py`, `bin/eval-hygiene.py`) |

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
  docs/evaluations/   Eval reports + index (what the factory verified and how)
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

| Project | Status | Vision | Docs |
|---------|--------|--------|------|
| `llm/` | Inference server. ✅ Running | [VISION](../llm/docs/vision/VISION.md) ✅ | [openwiki](../openwiki/projects/llm-server-client.md) |
| `survival-infrastructure/` | Personal intelligence pipeline. 🟡 Broken preflight | [VISION](../survival-infrastructure/docs/technical/VISION.md) ✅ · [TECHNICAL](../survival-infrastructure/docs/technical/TECHNICAL_VISION.md) ✅ | [openwiki](../openwiki/projects/survival-infrastructure.md) |
| `feed_analyser/` | Capture instrument: thin Chrome extension + minimal local server (legacy archived) | [capture VISION](../feed_analyser/capture/docs/vision/VISION.md) ✅ | [legacy archive openwiki](https://github.com/ak47-arch/feed_analyser/tree/main/archive/openwiki) |
| `headroom-pi/` | Compression proxy for pi. 🟡 Needs eval | [VISION](../headroom-pi/docs/vision/VISION.md) ✅ | project's own `openwiki/` |
| `workspace-portability/` | Backup/restore/bootstrap. ✅ Phase 1 done | [VISION](../workspace-portability/docs/vision/VISION.md) ✅ | project's own `openwiki/` |
| `resume/` | Resume editor. Deferred — not actively developed | ❌ Missing (deferred) | project's own `openwiki/` |
| `emotional_architecture/` | Personal operating manual. Static | — | — |
| `timesheetViewer/` | Timesheet validation. Deferred | — | — |

Vision-doc convention: [docs/vision-convention.md](vision-convention.md).

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
