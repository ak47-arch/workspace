---
name: eval-ops
description: Run contract for the autonomous evaluator agent. Defines the exact eval protocol — read the brief, orient on the eval surface, run the deterministic gold checks (bin/eval-decisions.py, bin/eval-pipeline.py), verify claim checks against the live repo/stack, assemble the fixed-schema outbox report, and write Langfuse scores via the synchronous scores endpoint. Add a robustness check here (a skill edit), never in the host driver.
---

# Eval Ops — Evaluator Worker Run Contract

This is the operational contract for the **evaluator** agent. You run eval panels over the
factory's own SDLC loops and report what you find. The host/session driver owns all git,
Langfuse prod writes, and any lifecycle transitions. You own the eval itself + the outbox report.

## 0. Read your brief first

Read `/sandbox/brief.md` (or the invoking session prompt) before anything else. It carries the
eval surface, working directory, Langfuse credentials/instance, the report path, and the binding
rules. The brief is authoritative for this run.

## 1. Orient

- The surface: which loop you are evaluating (decision / task / knowledge / prd-review). See the
  taxonomy in decision 01.
- The corpus: the artifacts for that surface under `docs/` (and their retained `.jsonl` under
  `docs/knowledge/sessions/`).
- The gold checks defined for the surface (deterministic PASS/SKIP with concrete evidence).

## 2. Run the deterministic panel

Use the surface's panel script:

- Decision-record loop: `python3 bin/eval-decisions.py`
- Task loop: `python3 bin/eval-pipeline.py`

If the surface has no script yet, run the checks directly (schema, session-link, claim-vs-repo).
Record the script exit + the produced `docs/evaluations/<date>-<surface>.{json,md}`.

## 3. Verify claim checks against the live repo/stack

For every deterministic claim in a record, verify it against the current tree/stack, not a stale
assumption. Examples from the seed:

- `LANGFUSE_MIGRATION_V4_WRITE_MODE=dual` — verify the running worker (`podman exec`), the
  compose anchor, and the gitignored `opensource/langfuse/.env`. A recreate from a compose
  that has lost the pin silently falls back to `events_only` and breaks pi tracing — this is a
  FAIL with evidence, even if runtime looks fine today.
- Session link: the decision's `session.jsonl` must resolve; a missing `.jsonl` is a real FAIL
  (retention gap), not a parser error.
- Path claims: only skip when a claim genuinely cannot be checked (tag `SKIP`, never `FAIL`).

Treat `SKIP` (non-checkable) as honest — do not force a verdict.

## 4. Assemble the outbox report (fixed schema)

Write `report.md`:

```
# Eval Report
- Surface: <decision | task | knowledge | prd-review>
- Date: <yyyy-mm-dd> · Eval session: <uuid>
- Report path: <docs/evaluations/<date>-<surface>.md>

## Verdict
PASS | FAIL (fleet) — <one line>

## Checks
- [PASS|FAIL|SKIP] <artifact> — evidence.

## Scores written to Langfuse
- <trace_id>: factory:decision-holds = <1|0> · evidence = <first 60 chars>

## Findings
- <artifact>:<detail> — why it fails.

## UAT hand-off list
- <precise items for the user>
```

## 5. Write Langfuse scores (v4 dual-mode caveat)

- Match the live trace by first user message (trace `name` = first prompt, truncated 1000).
- Post via the **synchronous** `POST /api/public/scores` endpoint with
  `dataType: NUMERIC`, `value: 1.0` (PASS) or `0.0` (FAIL), `comment` = evidence head.
- Do **not** use the batch `/api/public/ingestion` score-create path: in v4 dual mode it accepts
  `201` but silently never persists (verified 2026-08-20). Use the single-score endpoint.
- Unmatched traces stay report-only.

## 6. Finish

Exit 0 on a complete report; exit 1 if you must hand back a partial report. Either way
`report.md` is written. The host reads the outbox, archives it into `docs/evaluations/`, and
posts scores. You never do any of that.