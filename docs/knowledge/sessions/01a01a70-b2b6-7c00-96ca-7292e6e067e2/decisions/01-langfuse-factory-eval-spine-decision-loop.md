## Decision: Langfuse factory-SDLC eval spine — seed on the decision-record loop, deterministic-then-grounded

**Status**: accepted
**Date**: 2026-08-19 21:42
**Task**: [langfuse-agentic-operations](../../../../tasks/langfuse-agentic-operations.md)
**Project**: langfuse-agentic-operations
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Build one shared eval spine (session/trace → artifact/label → gold check → Langfuse dataset/score), written for a single surface first.

### Context

Requirement change 2026-08-19 (recorded in `docs/tasks/langfuse-agentic-operations.md` §Requirement change
and [langfuse-agentic-operations](../../../../prd/2026-08-09-langfuse-agentic-operations.md) §Requirement change): deliverable C is
re-scoped so the **software factory's own agentic SDLC** is the first-class Langfuse eval target;
first-party app integration is deferred follow-on.

The factory already produces many **closed, independently-traceable loops**, each with its own full
retained session file (decision 06 keeps complete sessions for Langfuse retrospective evals) plus a
recorded artifact (task file, decision record, knowledge entry, verdict). Langfuse already holds
~740 traces covering the prd-reviewer gates, implementer runs, and code-reviewer re-reviews
(2026-07-23 → 2026-08-19).

### Problem

Multiple evaluable surfaces exist (decision records, task lifecycle, knowledge-base entries, PRD
gates, review verdicts), and the data shape is unusual: the unit is a **process-run**, not a prompt;
gold is partly **self-referential** (a reviewer verdict grading its own implementer is circular) and
partly **independent** (merged tasks, later-falsified decisions); and rich **deterministic** signal
already exists (verdict strings, revision counts, exit codes, state transitions, claim-vs-repo
checks). We must start small, prove value, and extend over time — without building a generic eval
monolith up front.

### Alternatives

1. **Generic LLM-as-judge harness first** — heavier, carries circular-gold risk, needs calibration
   before it is trustworthy, and obscures the deterministic signal we already have.
2. **Manual annotation queue first** — high demo value (matches lesson 2's score/queue work) and
   builds ground truth, but human-paced and slow to produce fleet coverage.
3. **Deterministic seed on the decision-record loop first (chosen)** — smallest self-contained
   surface with a fixed schema and verifiable "still holds" gold; proves the whole session→artifact→
   gold→panel spine with zero LLM and no calibration.

### Decision

- Build **one shared eval spine** (session/trace → artifact/label → gold check → Langfuse
  dataset/score), written for a single surface first. Generalize into a **loop-registry** only when a
  second surface (task loop) lands — no premature abstraction.
- **Seed surface = decision-record loop**, scored by three deterministic checks:
  1. **Claim-vs-reality**: a decision's "still holds" claim is verified against the live stack/repo
     (e.g. Write mode still `dual` in `docker-compose.yml`; platform still 4.6.0 / healthy).
  2. **Referential integrity**: the decision's session link and referenced paths resolve.
  3. **Schema compliance**: `Status:`/`Date:` present and well-formed.
  Pass/fail per record → one Langfuse panel row per decision, full session attached. No LLM.
- **Session source = live Langfuse traces** (zero new plumbing); retain the `.jsonl` (decision 06)
  as the backfill path for loops that were never traced live or after an outage. Do not build an
  import pipeline up front.
- **Gold progression** (extend over time): deterministic → grounded LLM-judge (calibrated against
  an annotation queue) → cross-run drift/regression (L2). The path is
  deterministic → grounded judge → calibration → drift.

### Extension map (each step adds rows to the shared registry, not new machinery)

1. Seed — decision-record loop (above).
2. Task loop — `docs/tasks/*.md` lifecycle states joined to their sessions; gold = reached target
   state + revision-count/blocked signals. (This is where the registry abstraction earns its keep.)
3. Knowledge-base loop — `docs/knowledge/index.md` rows + own sessions; gold = index still true
   (links resolve, description still matches source).
4. PRD / review loop — verdict vs merged outcome (APPROVE → no post-merge revert); needs a ground
   truth bootstrap (annotation queue → calibrated LLM judge).
5. Cross-loop drift (L2) — run #1–4 on every new task, track drift vs accepted-decision history:
   "is the factory getting better", the verifiable-quality mission goal.

### Rationale

Deterministic-first because the decision-record surface is schema-compact, its gold is checkable
without an LLM, and it yields honest regression signal at near-zero cost — while a generic judge
first would recycle self-referential gold (the very bias we aim to catch) and hide the deterministic
signal. Smallest-surface-first matches the user's lesson-by-lesson and "least complex option"
preferences, and the task first step proves the spine before generality is worth paying for. Live
traces over a fresh import pipeline avoids new plumbing while decision 06's retained `.jsonl`
covers the untraced/outage gap.

### Consequences

- The eval surface for deliverable C is now primarily the factory's own SDLC loops, seeded by
  the decision-record loop; the PRD's "Open (under discussion)" item now points at this decision.
- First-party app integration remains deferred follow-on; app eval continues to be a later phase.
- The spine+panel design carries forward to the task, knowledge, and PRD/review loops.
- A "deterministic check" on decisions with non-checkable claims is a **skip** (not a fail) — only
  the deterministic subset is scoped in the seed.

### Revision triggers

- If a proven "still holds" check cannot be expressed deterministically for a decision, promote it
  to a grounded LLM check + annotation-queue calibration.
- The loop-registry abstraction is introduced at surface #2 (task loop), not before.
- If Langfuse's v4 events-style eval attachment does not fit the "one panel row per decision"
  shape, reassess the panel persistence (the official skills `trace-evaluator-upgrade.md` /
  observation-target guidance governs).
