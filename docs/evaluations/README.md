# Evaluation — Factory Eval Home

Home of the **evaluation** component (the software factory's continuous-quality discipline,
decision 02). Eval panels land here as `<date>-<surface>.{json,md}` reports — the standing answer
to "is the factory still doing what it decided / did the loop produce the predicted outcome?"

## What an eval report is

A fleet-level panel. One row per artifact, each evidence-anchored to:

- the **session** (`.jsonl`, decision 06 keeps full sessions for drift-off evals);
- the **artifact** graded (decision record, task file, knowledge row, review verdict);
- the **gold check** (deterministic PASS/SKIP/FAIL with concrete evidence);
- the **verdict** (PASS / SKIP / FAIL);
- where tracked, the **Langfuse trace** + score write-back (`factory:decision-holds`).

The spine (decision 01): `session/trace → artifact → gold check → panel row → Langfuse score`.

## Surface taxonomy

| # | Surface | Tool / report | Verdict meaning |
|---|---|---|---|
| 1 | Decision-record loop | `bin/eval-decisions.py` → `decisions.{json,md}` | schema + session-link + claim-vs-repo (deterministic); SKIP if nothing checkable |
| 2 | Task loop | `bin/eval-pipeline.py` → `pipeline.{json,md}` | reached state + revision / blocking signals |
| 3 | Knowledge loop | (register later) | index rows + own sessions |
| 4 | PRD/review loop | (register later) | APPROVE → no post-merge revert (independent gold only) |
| … | drift (L2) | (register later) | cross-run: did the earlier decision hold |

Deterministic-first (decision 01): a non-checkable row is **SKIP**, not FAIL. Grounded LLM-judge and
L2 drift are later tiers, registered only as the corpus + annotation queue grow.

## Scoring caveat (verified 2026-08-20)

- Write v4 scores via **`POST /api/public/scores`** (`dataType: NUMERIC`, `value: 1.0`/`0.0`,
  `comment` = brief evidence). The batch `/api/public/ingestion` score-create path returns 201 but
  silently drops score events in v4 dual mode — do not use it.
- Match traces by first user message (trace `name` = first 1000-char prompt); unmatched rows stay
  report-only.

## Produced reports

| Date | Surface | Verdict |
|---|---|---|
| 2026-08-14 | task loop | `2026-08-14-pipeline.{json,md}` |
| 2026-08-20 | decision loop | **PASS 21 / FAIL 2 / SKIP 96** (119 decisions) → `2026-08-20-decisions.{json,md}` |

> **The 2 failures on master are the seed's real findings**, not noise: the two gaps the eval loop
> surfaced (a missing `session.jsonl` retention entry + the `docker-compose` dual-mode pin drift).
> Their fixes are landed on bookkeeping PR **#24** (branch `factory/langfuse-eval-decisions/20260819`,
> unmerged). Once it merges, re-running `bin/eval-decisions.py` resolves them and the panel goes
> fully green — the panel is honest about living master, not about the work in flight.

## Authoring / maintenance

- **Run**: `python3 bin/eval-decisions.py` (decision loop) or `python3 bin/eval-pipeline.py` (task loop).
- **Persona**: read-only `evaluator` (`docs/factory-context.md` roster; `.pi/agents/evaluator.md`;
  run contract `.agents/skills/eval-ops/SKILL.md`; artifact map `docs/reference/evaluator-agent.md`).