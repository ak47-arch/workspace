## Decision: Evals integrated as a software-factory department (the evaluation component)

**Status**: accepted
**Date**: 2026-08-20 00:20
**Task**: [langfuse-agentic-operations](../../../../tasks/langfuse-agentic-operations.md)
**Project**: langfuse-agentic-operations
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Evals are a named fifth component of the factory: the evaluation component.

### Context

Decision 01 (`01-langfuse-factory-eval-spine-decision-loop.md`, 2026-08-19) proved the eval
spine (session/trace → artifact → gold → Langfuse panel) on the decision-record loop
(seed-1): deterministic checks, one row per decision, score written back to the live trace.
The user now wants evals to stop being a one-off analysis and become a **standing discipline
of the factory itself** — a component staffed like the other SDLC stages, so the factory's
own quality is continuously verified and feeds learning ("quality is verifiable, not vibes").

### Problem

Evo have worked as ad-hoc scripts (`bin/eval-decisions.py`, `bin/eval-pipeline.py`) and
ad-hoc reports (`docs/evaluations/<date>-*.{json,md}`). Without a home they are undiscoverable
(a future session would grep for them), not registered in the factory model (`docs/factory-context.md`
has four components, evals fit none), and not staffed — nothing says *who runs an eval loop, with
what contract, and where the evidence lands*. The discipline therefore does not compound; each run
starts from tribal knowledge.

### Alternatives

1. **Keep ad-hoc** — lowest cost, but no discoverability, no staff, no compounding; exactly the
   gap the user is asking to close.
2. **Fold evals into an existing department** (e.g. the assembly line or project management) —
   avoids a new component, but the eval contract and its runbook/evidence don't fit any existing
   stage's brief (they are cross-loop and read-only), so it would be swallowed and never
   documented.
3. **A dedicated eval department (chosen)** — a fifth component with its own roster row,
   run-contract skill, artifact map, and evidence index, mirroring how implementer/reviewer/
   prd-gate are each staffed. This is the smallest shape that makes evals discoverable,
   ownable, and compounding.

### Decision

Evals are a **named fifth component** of the factory: the **evaluation** component. It is
staffed (roster) by an **evaluator** agent, instructed by an eval-ops run-contract skill,
with a reference artifact map and a home at `docs/evaluations/`.

Concretely:

- **Component entry**: add "evaluation" to `docs/factory-context.md` (the four existing
  components + one); note it is cross-cutting and read-only (runs panels, never mutates a
  target repo; it writes only its own `docs/evaluations/` reports and Langfuse scores).
- **Roster row**: `.pi/agents/evaluator.md` — the evaluator agent; added to the agents table
  with its SDLC stage ("production eval / continuous quality"), role, and run instructions.
- **Run contract**: `.agents/skills/eval-ops/SKILL.md` — the operational contract for a headless
  eval run: orient on the eval brief, select the surface, run the deterministic panel
  (`bin/eval-decisions.py`, `bin/eval-pipeline.py`), verify claim checks against the live
  repo/stack, assemble the fixed-schema eval report, write evidence + scores. Follows the
  `review-ops`/`implementer-ops` skill pattern.
- **Artifact map**: `docs/reference/evaluator-agent.md` — one-hop map of where every eval
  artefact lives (same why as `implementer-agent.md` / `reviewer-agent.md`).
- **Evidence + index**: `docs/evaluations/README.md` — the eval department home: what an eval
  report is, the surface taxonomy, how evidence is anchored (linked session, artifact, check,
  verdict, trace), and index of produced reports.
- **The eval evidence is self-documenting**: each panel report carries the session link, the
  artifact it graded, the deterministic checks with pass/evidence per check, and the Langfuse
  trace's score write-back.

### Rationale

Dedicated-component is the least complexity that closes the real gap (discoverability,
ownership, contract). It reuses the factory's proven shape for staffing — the same pattern as
`prd-reviewer` / `implementer` / `code-reviewer` — so no new machinery is invented; evals slot
into the discovery layer (`.agents/skills/`) and the progressive-disclosure chain (`docs/evaluations/`)
like any other discipline. It "compounds" the seed: each future surface (task, knowledge, PRD/
review, drift) registers rows in the eval report, not new machinery — exactly the extension map
in decision 01.

### Consequences

- Five components now: context_engine, product/architecture, project_management, assembly_line,
  + **evaluation**.
- A fifth roster agent (evaluator) with a read-only run contract; it never merges, never
  completes, never edits a target repo — only `docs/evaluations/` reports + Langfuse scores.
- Eval artifacts have a permanent home and an index: `docs/evaluations/README.md` + per-date
  reports; the run-contract skill makes the discipline summonable by name from a session.
- The seeds (decision + task loops) are the component's first two surfaces; grounded-judge and
  drift (L2) are registered later as the eval corpus and annotation queue grow.

### Revision triggers

- If the eval departments becomes part of the assembly line (e.g. a scheduled
  CI step), reconsider whether it deserves a top-level component.
- If a second team starts producing evals, promote `docs/evaluations/README.md` to a shared
  index with per-surface subdirectories.
- If the factory model changes (a component is renamed/removed), keep "evaluation" in the
  progressive-disclosure chain and roster.
