# Factory Eval Surfaces — Register & Evolution Log

Breadth-first register of every **eval surface** the evaluation department may open over the
factory context and its applications. Owned by decision 02 (`evaluation` component) and its
context-engine focus (decision 03). **Depth-first passes into each surface come later** — this
document is the breadth-first map: what surfaces exist, what each would grade, and how the set has
grown.

Read top-down as an **evolution timeline**: each surface accrues a dated row when it is *declared*
(registered) and when it is *opened* (a live panel exists). The register is the standing answer to
"how many ways do we grade the factory, and which are actually emitting signals right now?"

---

## Living status legend

- **🔵 declared** — the surface is identified + scoped (verdict meaning defined), no panel yet.
- **🟢 live** — the surface has a working panel (`bin/*.py` → `docs/evaluations/<date>-<surface>.{json,md}`)
  and emits signals (Langfuse `factory:*` scores on matched traces).
- **🟡 deferred** — scoped but blocked (typically awaiting app preflights).

---

## Surface register

| # | Surface | Tool / report | Verdict meaning | Status | Opened |
|---|---|---|---|---|---|
| S1 | **Decision-record loop** | `bin/eval-decisions.py` → `decisions.{json,md}` | schema + session-link + claim-vs-repo holds; SKIP if nothing checkable | 🟢 live | 2026-08-20 |
| S2 | **Task loop** | `bin/eval-pipeline.py` → `pipeline.{json,md}` | reached target state + revision/blocking signals | 🟢 live (gaps-only today) | 2026-08-14 |
| S3 | **Knowledge loop** | (register later) | index rows ↔ own sessions; context-engine consistency | 🔴 declared | — |
| S4 | **PRD/review loop** | (register later) | APPROVE → no post-merge revert (independent gold only) | 🔴 declared | — |
| S5 | **Drift / L2** | (register later) | cross-run: did the earlier decision hold | 🔴 declared | — |
| S6 | **Stack-liveness (infra)** | (new) | 6 container services up; tracing live; **dual-mode invariant** held | 🔴 declared | — |
| S7 | **Context-engine surface** | (new) | footprint/leanness + retrieval reachability + summary fidelity of the factory's own context | 🔴 declared | — |
| S8 | **Roster completeness** | (new) | every worker has persona + run-contract + artifact-map (closed closed loop) | 🔴 declared | — |
| S9 | **Repo-hygiene** | (new) | master merge-only; `opensource/` gitignored; PRs reviewed; no secrets | 🔴 declared | — |
| S10 | **App family** | (register per app) | tracepoint/extraction/inference quality — the signal the context engine eats at production volume | 🟡 deferred | — |
| &#8239; | … | | | | | |

---

## Evolution log

Chronological record of when each surface was declared / opened and what it surfaced. This is the
"documenting the evolution" spine — every expansion row below is reversibly tracked.

### 2026-07 → 08 (seed era)
- **Seed-1 (decision-record loop)** — S1 birthed as the first surface: deterministic panel over all
  decision records (schema, session-link, claim-vs-repo). First real signal: **2 FAILs**
  (missing `session.jsonl` retention + compose dual-mode drift), both fixed on PR #24. Re-ran green:
  **PASS 22 / FAIL 0 / SKIP 98** on master.
- **S2 task loop** opened — `eval-pipeline.py` joins 26 tasks ↔ PR tracking ↔ review reports. Today
  only reports **schema gaps** (not yet a PASS/FAIL panel — depth-first work pending).

### 2026-08-20 (breadth push — this register)
- **S3 S4 S5** formalized (declared) from the taxonomy.
- **S6–S9 added** — new breadth beyond the original five, each choosing a concrete factory invariant.
- **S10** registered as the deferred app gate (the moment app preflights clear, these open).
- Decision 03 recorded: eval signal feeds the **context engine** — so S7 (engine-surface) is named
  **the** headline surface, matching the mission.

---

## How a surface earns signals (the common spine)

Every surface — declared or live — grades through the same spine (decision 01):

`session/trace → artifact → gold check → panel row → Langfuse score`

The **gold check** is deterministic-first: PASS or FAIL only when a repo/stack observable proves the
claim; otherwise **SKIP** (never forced). A row grades the factory's *own* context; the panel's
score exhausts onto matched Langfuse traces (`factory:decision-holds`), which is the standing
health readout.

Breadth-first means: we open more surfaces before deepening any single one. Depth-first (per-surface
dives into richer checks, then the grounded-judge + drift tiers) follows in later passes.

---

## Drift of curation (off-road anti-goal)

- SKIP is honest, not shame: a non-checkable row stays SKIP until a checkable claim exists.
- No circular self-gold: the reviewer-grades-own-implementer loop is a **failure state** (decision 01);
  reviewer-fidelity gold must be independent.
- No LLM-judge until the deterministic tier for that surface has covered what it can, and the judge
  is grounded + calibrated against independent gold.
- No finetune motive: eval output improves the context engine (decision 03), not model weights.

---

> **Scoring caveat**: v4 scores must write via synchronous `POST /api/public/scores` (the batch
`/api/public/ingestion` path silently drops scores in v4 dual mode) — identical across every surface.