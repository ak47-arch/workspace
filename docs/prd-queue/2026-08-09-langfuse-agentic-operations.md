# PRD: Langfuse Agentic Operations — official skill integration, platform operations, and first-party app tracing

**Date**: 2026-08-09
**Status**: Draft (amended 2026-08-19 — requirement change, see below)
**Owner**: software-factory workspace
**Task**: langfuse-agentic-operations
**Session**: `docs/knowledge/sessions/019fc40a-5458-7310-89c4-53e098060973/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019fc40a-5458-7310-89c4-53e098060973/decisions/01-langfuse-v3-to-v4-upgrade.md`

## Problem statement

Three lines in `docs/tasks.txt` converge on one goal: make Langfuse the observability
and evaluation backbone of the workspace, operated agentically, and teach the user how
to use it (see `docs/teach/langfuse/MISSION.md` — "quality is verifiable, not vibes").

Today: the platform self-hosts at `opensource/langfuse/` (now v4.6.0) and pi's own agent
turns are traced live via the extension at `.pi/extensions/langfuse-tracing.ts`. But:

1. **Skill fragmentation** — the official Langfuse skill
   (`opensource/langfuse-skills/skills/langfuse/`) holds deep upstream knowledge, yet the
   thin wrapper `.agents/skills/langfuse-tracing/SKILL.md` originally pointed nowhere: no
   delegation, no ops, no version notes. Agents could not reliably find "how to Langfuse".
2. **No platform operations** — start/stop/restart/health/logs was tribal knowledge. The
   stack silently ran down for 3 days (discovered 2026-08) with no documented recovery.
3. **Upgrade hazard discovered** — v3→v4 migration broke ClickHouse data (4200 observations
   wiped from live, traces table dropped) and v4's default `events_only` write mode rejects
   `trace-create` ingestion events, silently killing pi tracing. Both are now fixed
   (`dual` mode, data restored), but the lessons must be captured as operations guidance.
4. **No first-party coverage** — every first-party app (`llm/`, `survival-infrastructure/`,
   `headroom-pi/`, `feed_analyser/capture/`, etc.) has **zero Langfuse references** despite
   heavy LLM/agent usage.

## Solution overview

Three deliverables, one coherent system:

**A. Thin wrapper skill with delegation.** `.agents/skills/langfuse-tracing/SKILL.md` is the
single entry point. It: (i) points to the official skill's location and index of references
without copying; (ii) carries only company-specific facts (our stack, credentials, v4 notes,
recovery); (iii) now includes the Level-B operations sheet (start/stop/restart/health/logs).
The official skill repo is updated by fast-forward pull only — never hand-edited.

**B. Agentic operations (Level B).** Documented runbook inside the wrapper: 6 containers
(postgres, redis, clickhouse, minio, web, worker), podman socket export, health bar
(`/api/public/health` 200), log tails, dirty-migration recovery pointer. No continuous
monitoring/alerting in scope (Level C deferred).

**C. First-party integration plan.** Inventory surveyed (7 projects; pi integrated today,
`llm/` and `survival-infrastructure/` high priority, phases defined). Execution begins when
the 🟡 preflight stacks are running.

## User stories

1. As a developer, when I need Langfuse guidance, I read the wrapper skill and am routed to
   the official skill's topic docs — no duplication, no guesswork.
2. As an operator, when the stack is down, I run the documented start/health sequence and
   know the health bar is `/api/public/health` returning 200.
3. As a user of evals, I can trace any first-party app's LLM activity and evaluate it in
   Langfuse v4 (observations-first eval rules) without per-app tribal knowledge.
4. As a maintainer, when upgrading Langfuse, I know `LANGFUSE_MIGRATION_V4_WRITE_MODE` must
   stay `dual` (or pi tracing silently breaks) and where the dirty-migration recovery record
   lives.

## Implementation decisions

- **Wrapper-delegation over copying**: thin wrapper points to official skill location; no
  file duplication. Company facts stay in wrapper; upstream knowledge stays upstream.
- **Operations as a section in the wrapper SKILL.md** (not a separate script) — least
  complexity; matches "always choose the least complex option".
- **Level B scope** for operations: start/stop/restart/health/logs. Level C (continuous
  monitoring, alerting) explicitly out of scope.
- **Health bar is the web endpoint** `/api/public/health` returning 200 — deeper checks are
  overkill.
- **Write mode stays `dual`**: `LANGFUSE_MIGRATION_V4_WRITE_MODE=dual` in
  `docker-compose.yml` (compose anchor) and `.env` — v3 ingestion (`trace-create`) works and
  v4 events architecture is enabled. Never switch to `events_only` (rejects pi ingestion).
- **v4 eval models**: eval rules target observations/experiments, not traces (per official
  `trace-evaluator-upgrade.md`); teaching follows v4-native shapes.
- **Integration order**: `llm/` client first (single choke point) → `survival-infrastructure/`
  → phase 2 (`headroom-pi/`, `feed_analyser/capture/`) → skip `resume/` (deferred).
  **Amended 2026-08-19**: superseded by the requirement change below — factory SDLC
evals first, app integration deferred.

## Requirement change (2026-08-19)

**Change**: deliverable C re-scoped. The **software factory's own agentic SDLC loops**
become the first-class eval target; first-party app integration (`llm/`,
`survival-infrastructure/`, phase-2 apps) is deferred follow-on, keeping the existing
inventory + phases unchanged.

**Why**: the factory's closed loops are already traced live to Langfuse (prd-reviewer
gates, implementer runs, code-reviewer re-reviews all present as traces,
2026-07-23 → 2026-08-19) and every run retains its full session plus run
manifests/verdicts, knowledge decision records, and task lifecycle states — the
richest evaluable corpus available today. App eval has lower marginal value now.

**Amends**: the "Integration order" implementation decision above; out-of-scope item
"Actual code changes inside first-party apps (inventory + plan only; execution is
follow-on)" now reads "deferred until the factory SDLC eval layer is live".

**Open (under discussion)**: eval surface taxonomy, per-loop eval approach (annotation
queues → LLM-as-judge on v4-native observations → cross-run regression), and whether
evals run on live per-run traces or on retained session `.jsonl` imports. **Resolution
2026-08-19**: decided — one shared eval spine, seeded on the decision-record loop with
deterministic checks on live traces, extending surface-by-surface; see
`docs/knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/decisions/01-langfuse-factory-eval-spine-decision-loop.md`.

**Resolution 2026-08-20**: evals are **integrated as a dedicated factory department** — a fifth factory
component (decision
`docs/knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/decisions/02-eval-factory-department.md`): roster
`evaluator` agent (`.pi/agents/evaluator.md`, run contract `.agents/skills/eval-ops/SKILL.md`, artifact map
`docs/reference/evaluator-agent.md`), report home + index `docs/evaluations/README.md`. Seed surfaces
(decision-record + task loops) tooled by `bin/eval-decisions.py` / `bin/eval-pipeline.py`; grounded-judge
and L2 drift register later per decision 01's extension map. App eval stays a deferred follow-on.

## Testing decisions

- Smoke: `docker-compose up -d` → all 6 containers healthy → `curl /api/public/health` = 200.
- Pi extension: POST a `trace-create` via `/api/public/ingestion` — expect `201` successes,
  `[]` errors (dual mode). Fails on `events_only` with "Event type not accepted".
- Data integrity: ClickHouse `traces`/`observations` counts stable across restart; the
  2026-08-09 restore (4,293 observations, 339 traces) is the baseline.
- Skill validation: read wrapper → every path it references exists
  (`opensource/langfuse-skills/skills/langfuse/SKILL.md` + 11 references).

## Out-of-scope

- Level C operations (continuous monitoring, alerting, uptime SLOs).
- Actual code changes inside first-party apps (inventory + plan only; execution is follow-on).
- Migrating pi extension to the v4 events ingestion API (only when upstream deprecates `dual`).
- `resume/` project integration (deferred).

## Further notes

- Teaching workspace `docs/teach/langfuse/` runs in parallel (lesson 1 done: trace anatomy;
  lesson 2 = scores on v4). The PRD's eval guidance feeds those lessons.
- The 2026-08-07 official-skill pull (`b9958d6`) removed stale guidance; wrapper tracks repo
  currency via `git pull --ff-only`.
- Known loss: one manual demo score (`task-completion`) from the pre-upgrade era — recreatable;
  score config infra in Postgres intact.

## Architecture

```
┌─────────────────────────── workspace ───────────────────────────┐
│  .agents/skills/langfuse-tracing/SKILL.md  (thin wrapper)        │
│    ├─ Official skill pointer ─┐                                  │
│    ├─ Company stack facts      │  (delegation, no copy)          │
│    ├─ Operations runbook (B)   │                                 │
│    └─ v4 notes                 │                                 │
│                                ▼                                 │
│  opensource/langfuse-skills/skills/langfuse/  (official skill)   │
│    SKILL.md + 11 references (cli, evals, judge-calibration,…)    │
│                                                                  │
│  .pi/extensions/langfuse-tracing.ts → POST /api/public/ingestion │
│                                          │                       │
│                                          ▼                       │
│  opensource/langfuse/  docker-compose (6 containers, v4.6.0)     │
│    LANGFUSE_MIGRATION_V4_WRITE_MODE=dual  (v3 ingest + v4 events)│
│    ClickHouse: traces, observations, events_core/events_full, …  │
│                                                                  │
│  First-party apps (plan): llm/ → survival-infrastructure/ → …    │
└──────────────────────────────────────────────────────────────────┘
```

## Program Design

**Phases**:

1. **Platform stable** (done 2026-08-09): v4 upgrade, data restore, `dual` mode, health 200,
   live pi tracing verified.
2. **Skill works** (done 2026-08-09): wrapper has official-skill delegation + ops + v4 notes;
   official skill repo current; paths verified.
3. **Ops runbook usable** (done 2026-08-09): Level-B table lives in wrapper; commands verified
   against the live stack.
4. **Cross-app plan documented** (done 2026-08-09, execution pending): inventory + phases in
   task file.
5. **Evals teaching** (in progress): lesson 2 (scores) → LLM-as-judge on v4; uses the official
   skill and v4-native observation targets.
6. **Integration execution** (follow-on): wrap `llm/` client; instrument
   `survival-infrastructure/`; then phase-2 apps — each gated on its stack preflight passing.
7. **PRD sign-off + archive**: user signs off; task transitions to complete; knowledge
   decisions recorded per session.