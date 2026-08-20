# Evaluator Agent — Artefact Map

**Why this document exists**: like the implementer/reviewer, the evaluator is deliberately NOT
consolidated into a single folder. Its persona, run contract, tooling, and evidence each live where
their ownership model says they belong. This map is the navigation aid — read it instead of grepping.

**What the evaluator is**: the worker that staffs the **evaluation** component of the software
factory — the continuous-quality discipline. It runs eval panels over the factory's own SDLC loops
(decision records, task lifecycle, knowledge-base entries, PRD/review verdicts) via the eval spine
(target → artifact → gold check → Langfuse panel), and reports PASS/SKIP/FAIL with evidence. It is
cross-cutting and **read-only** — it never merges, never completes, never mutates a target repo;
it writes only `docs/evaluations/` reports and Langfuse scores.

**Core rule**: the eval evidence is self-documenting. Every report row carries the session link, the
artifact graded, the deterministic checks with pass/evidence per check, and the Langfuse trace's
score write-back. The discipline compounds because new surfaces (task, knowledge, PRD/review, drift)
register rows in the report rather than new machinery (decision 01 + decision 02).

---

## Artefact map

| Artefact | Location |
|---|---|
| Worker persona / brief | `.pi/agents/evaluator.md` |
| In-container run-contract skill | `.agents/skills/eval-ops/SKILL.md` |
| Decision-record panel tool | `bin/eval-decisions.py` → `docs/evaluations/<date>-decisions.{json,md}` |
| Task-loop panel tool | `bin/eval-pipeline.py` → `docs/evaluations/<date>-pipeline.{json,md}` |
| Report home + index (the department's home) | `docs/evaluations/` (`README.md` + per-date reports) |
| Langfuse self-host + credentials | `.env.langfuse` / `opensource/langfuse/` (gitignored) |
| Trace-to-session match | pi extension `.pi/extensions/langfuse-tracing.ts` (name = first 1000-char prompt) |

## Design authority

- **Decision 01** — `…/decisions/01-langfuse-factory-eval-spine-decision-loop.md` — the spine,
  surface taxonomy, gold progression (deterministic → grounded judge → drift).
- **Decision 02** — `…/decisions/02-eval-factory-department.md` — evals as a factory component
  (this document's justification).
- v4 dual-mode + score-path caveat: see `docs/knowledge/sessions/019fc40a-…/decisions/01-langfuse-v3-to-v4-upgrade.md`
  + the score-path caveat in `.agents/skills/eval-ops/SKILL.md`.

## Operationally

Run (or hand to the evaluator) on demand:
- `python3 bin/eval-decisions.py` — decision-record panel (schema, session-link, claim checks).
- `python3 bin/eval-pipeline.py` — task-loop panel (tasks ↔ PR ↔ impl ↔ reviews ↔ traces).

The evaluator agent is invoked read-only (e.g. via the eval-ops short). It emits the report; no PR
is raised by the evaluator themselves.