# PRD: Context-Disclosure Semantic Probe Contract

**Date**: 2026-08-21
**Status**: Draft
**Owner**: software-factory workspace
**Task**: context-disclosure-semantic-probe
**Session**: `docs/knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/decisions/02-eval-factory-department.md`
  - `docs/knowledge/sessions/01a01a70-b2b6-7c00-96ca-7292e6e067e2/decisions/03-eval-feedback-target-context-engine.md`

## Problem statement

Decision 03 (`03-eval-feedback-target-context-engine.md`) sets the evaluation department's
headline: *does the context engine get better at feeding the factory's agents?* The quality
lever in a scripted-deterministic factory is **how well the factory feeds its agents** — not
model capability (the model is a given, provably competent, and publicly available).

The deterministic tier (S7 C1–C5) verifies the spine as *static documents*: links resolve,
sections stay within token budgets, no dangling back-references. But it **cannot answer the
semantic readiness question**: given an agent about to act on a specific task, did the
disclosure chain actually *hand it the single governing answer it needs to proceed* — within
budget, in the hops the engine expects? Deterministic checks treat the spine as reachable;
nothing verifies it as **fit-for-purpose per task**. "Continuous quality" that never asks
this stays a bookkeeping facade.

Today there is no contract that a task archetype's "needed-binding" is reachable before the
engine is trusted. The engine can be inside rules yet still fail the agent by burying the one
governing probe (the PRD acceptance criteria, the constraining decision, the knowledge row)
two disclosures deep.

## Solution overview

Introduce a **context-disclosure probe contract**: a per-task-archetype spec of "what each
roster role must be able to reach, at what hop, at what token cost", plus a **suite that
walks the disclosure chain cold** on real tasks and reports whether it delivered.

Two parts:

**A. The probe contract** — a declarative matrix. One row per task archetype (PRD-gate,
implementer, code-reviewer, evaluator), each declaring the "needed-binding" of that task:
which artifact must be reachable (PRD + acceptance criteria, the constraining decision, the
knowledge row, the review target), at what disclosure hop the engine promises it, and at
what token cost (bounded by the C1 budget for that layer).

**B. The probe worker** — `bin/eval-context-semantic.py`. For a real task, walks the
disclosure chain cold (reads only the spine + task file + `docs/knowledge/index.md`, no
memorized answer), and scores each archetype row:

1. **reachable**: the needed-binding was found at-or-before its promised hop.
2. **cost-to-anchor**: tokens spent before the binding surfaced (compared to the C1 budget).
3. **hops-to-anchor**: actual disclosure depth (vs the contract's promised hop).
4. **sufficiency**: the binding is present as a *specific answer*, not just the pointer.

Output = a report row per task with {reached?, hops, tokens, margin vs the real
session's spend}. Verdict on the surface is derived from aggregate: a row is FAIL if the
required binding was not reachable in-budget at the promised hop.

## User stories

1. As an **implementer**, when I pick a `Final` PRD, the context I am given contains the
   PRD acceptance criteria and the exact decision/knowledge rows that constrain this task at
   the disclosure level the engine promised — I never improvise a hidden-governing rule.
2. As a **code-reviewer**, when I review a PR, the chain hands me the PRD + diff + the drift
   row guarding the fix being reviewed at a hop that does not exceed the reviewer budget.
3. As the **context-engine owner**, I can see, per task archetype, whether the engine is
   feeding the needed-binding confidently or under-cost — and a systematic reach-miss is a
   disclosed defect, not agent error.
4. As the **evaluator**, I can register a semantic probe row per archetype that the engine
   must hold (via drift), so a future disclosure-path regression trips the panel. Not a
   can't-fail check — a measured readiness bar.

## Implementation decisions

- **Context-engine-centric only (decision 03 gate).** Every probe row must be an
  answerable "did the engine feed the needed binding reachable?" question. Rows that only
  re-measure deterministic PASS/FAIL of a script are rejected — that's the existing C-tier.
- **Probe contract is declarative, row per archetype.** contract lives at
  `docs/evaluations/context-probes.json`. No new machinery to encode the matrix: a JSON
  table of `{archetype, needed_binding, promised_hop, token_budget_row}`.
- **Cold-walk, no fresh-agent answer.** The probe worker replays a completed task's
  retained `session.jsonl` (its actual `read` tool calls) — not a fresh LLM walk. Ground
  truth is gold-from-work: what the real session reached, at what step, at what cost.
- **REACH is the hard gate; COST is advisory.** During the research build we found a subtle
  trap: comparing cumulative session read-tokens against C1's per-document budget is a
  category error (different units). So the probe FAILs only on REACH (session never read its
  bound PRD / binding missing on disk) and reports COST_TOGATE as an advisory leanness
  signal for later budget-setting — it never fabricates a threshold.
- **Validation against real work, not an LLM rubric.** Calibration = match the actual
  session's disclosure (injection-tested: removing a PRD flips that task's verdict to FAIL).
- **Drift-guarded.** A probe archetype row, once shown to trip (systematic reach miss),
  becomes a drift gold row (L2) so it cannot regress. And the panel after a fix recomputes
  both the semantic probe AND the drift row.
- **Score write-back shape.** Semantic verdicts write a continuous `0.0–1.0` value to the
  live Langfuse trace (synchronous `POST /api/public/scores`), plus the probes' aggregate
  margin. Binary bookkeeping stays the deterministic substrate; the headline becomes the
  disclosure-readiness score.

## Verification / testing

- **Cold-walk reality**: for a known-complete task (e.g. a merged PR and its session), the
  probe reports the same hop + binding the actual session reached (march-and-check).
- **Mis-disclosure injection**: deliberately remove a pointer binding from
  `factory-context.md` (or point a task's PRD link to the wrong knowledge row) — the probe
  for that archetype must flip to FAIL at the promised hop. This proves it is not a
  can't-fail check.
- **Budget guard**: a probe row that exceeds its C1-derived budget -> token cost → the
  archetype row FAILs with the overage.
- **Drift integration**: after a real probe trip + fix, the drift gold row for that
  archetype HOLDs green on subsequent runs.

## Out-of-scope

- Model capability / finetuning (explicitly against decision 03: no finetuning motive).
- LLM-judge-as-authority: the probe is deterministic cost/hop/reachability ground truth; it
  does not grade artifact prose as if reading it. (An LLM *probe driver* may be used to
  simulate the climber walk — but its classification is cross-checked against the real
  session's record, not trusted alone.)
- App-family (S10) semantic grading — apps still not running.

## Architecture

```
                          ┌─────────────────────────────┐
                          │  docs/evaluations/          │
                          │  context-probes.json         │  ← probe contract (matrix)
                          │  (archetype × binding × hop × budget)
                          └─────────────────────────────┘
                                   │
              bin/eval-context-semantic.py (probe worker)
                 ├─ replays a completed task's retained session.jsonl (its real read calls)
                 │   and checks whether the task's bound PRD was actually reached
                 ├─ resolves bindings across prd-queue/ AND prd-archive/ (archived PRDs)
                 ├─ measures step-to-gate + cumulative read tokens (COST, advisory)
                 └─ FAIL = binding unreached or missing on disk (REACH hard gate)
                          │
                          ▼
        docs/evaluations/<date>-context-semantic.{json,md}  (report)
                          │
                          ▼
        L2 drift gold row(s): reach/miss archetype (guarded)
                          │
                          ▼
        Langfuse score write-back (continuous 0.0–1.0) to live trace
```

## Program Design

**Status of this PRD as of 2026-08-21**: research prototype driven in-session (not staged
through the implementer). `bin/eval-context-semantic.py` is built, runs against the real
corpus, and passes the honesty gates below. Remaining work is production wiring (drift rows,
continuous score write-back) once the probe contract is formalised.

**Phases**:

1. **Probe matrix (breadth)**: the archetype ↔ binding ↔ hop contract landed as
   `docs/evaluations/context-contracts.json` (first gate: each row is a context-engine
   question).
2. **Probe worker**: `bin/eval-context-semantic.py` — cold-walk, measure, compare vs session
   ground truth. Runs read-only; writes only its report + scores.
3. **Calibration on real work (the honest zero-run)**: walk 5–10 real task→session↔decision↔PRD↔
   review chains cold; baseline: did the chain reach the binding under the C1 budget, at
   what hops/tokens, and does the real session's spend corroborate (was the binding the
   one the worker *actually* used)?
4. **Drift-armed operation**: register a drift gold row per archetype once its baseline
   pass is confirmed; then the semantic panel runs in operation.

## Note to the implementer

This PRD is **context-engine-centric** by design (decision 03): the deliverable is a
sufficiency probe contract for reading the disclosure chain, not a grader of artifact prose
and not a model-capability benchmark. The honesty rules from the register
(`docs/evaluations/surfaces.md` — "SKIP is honest", "no circular self-gold") apply to the
semantic tier too: a probe row must be falsifiable (the mis-disclosure flip test) and
its ground truth must come from real finished sessions, never from another LLM opining.