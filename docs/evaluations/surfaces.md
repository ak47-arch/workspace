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
| S2 | **Task loop** | `bin/eval-pipeline.py` → `pipeline.{json,md}` | T1 state-legal · T2 complete→archived (UAT gate) · T3 complete+PR→impl/rev evidence · T4 merged→APPROVE · T5 merged→complete · T6 queue-gate; zero-evidence completions = SKIP | 🟢 live | 2026-08-20 |
| S3 | **Knowledge loop** | `bin/eval-knowledge.py` → `knowledge.{json,md}` | K1 index links resolve (GFM anchors) · K2 session evidence · K3 every decision indexed | 🟢 live | 2026-08-20 |
| S4 | **PRD/review loop** | `bin/eval-prd.py` → `prd.{json,md}` | P1 PRD→task→PR-tracking · P2 review verdict + merge fidelity · P3 no post-merge revert (cross-repo SHAs unverifiable) · P4 report-body fidelity (final review matches report) · P5 approve-on-merge · P6 report→task resolution (no orphans) · P7 every PR reviewed | 🟢 live | 2026-08-20 |
| S5 | **Drift / L2** | `bin/eval-drift.py` → `{date}-drift.md` + `drift.json` (trend store) | cross-run: prior fixed findings stay fixed (HOLD/DRIFT, first/last-verified). Not liveness — liveness is ops | 🟢 live — 13 gold rows HOLD | 2026-08-20 |
| S6 | **Infra-invariant fidelity** *(superseded)* | — | liveness is ops, not eval (see anti-pattern note); invariant fidelity already covered by S1's dual-mode claim | 🔴 declared (retracted) | — |
| S7 | **Context-engine surface** | `bin/eval-context.py` → `{date}-context.{json,md}` + `context.json` (trend) | C1 footprint/leanness (budgets + 2× growth) · C2 spine-link reachability (GFM anchors) · C3 summary fidelity (5 components, roster, vision links, footprint claim) | 🟢 live | 2026-08-20 |
| S8 | **Roster completeness** | `bin/eval-hygiene.py` → `hygiene.{json,md}` | every worker has persona + run-contract + artifact-map | 🟢 live | 2026-08-20 |
| S9 | **Repo-hygiene** | `bin/eval-hygiene.py` → `hygiene.{json,md}` | master merge-only; `opensource/` gitignored; no secrets in tracked files | 🟢 live | 2026-08-20 |
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
- **S3 opened (live)** — `bin/eval-knowledge.py` knowledge-loop panel (the context engine's own
  wiring): K1 index-link integrity (GFM-anchor aware) · K2 decision→session evidence · K3 every
  decision indexed. First run: K1 false-positives (checker bug, fixed); **K3 real gap** — one
  orphaned decision (ponytail-skills-fixed-mount) never indexed → added to index; **PASS**.
- **S4 opened (live)** — `bin/eval-prd.py` PRD/review-loop panel: P1 PRD→task→PR-tracking, P2 review
  verdict + merge fidelity, P3 no post-merge revert. Initial findings + resolution:
  - **P1 (7 legacy tasks no PR-tracking)** — pre-date decision 06 (2026-08-14) convention; no PR
    ever existed. Marked honestly as pre-PR-era in each task; panel treats the marker as valid.
  - **P2 (implementer-ponytail "n/a" verdict)** — task file under-recorded review 3; the actual
    report (session 6b560fbb) said **APPROVE**. Corrected the task file; panel now reads real verdicts.
  - **P3** — cross-repo SHAs (feed_analyser) correctly unverifiable, not a revert. PASS.
- **S4 depth (P4–P7 added)** — extended the panel with four bounded guards, each corpus-checkable:
  - **P4 report-body fidelity** — the task's FINAL review verdict must match its review report body
    (only the last review is checked: the on-disk report reflects the final write; intermediate
    REQUEST_CHANGES history is legitimately overwritten). Validated by simulated-drift injection.
  - **P5 approve-on-merge** — a merged PR must carry APPROVE as its last verdict (a merged
    REQUEST_CHANGES/REVISE is a failure state). All 8 merged tasks APPROVE.
  - **P6 report→task resolution** — every review report dir maps to a real task (no orphan reports).
  - **P7 review-PR coverage** — every post-PR-era task with a PR has at least one review line
    (no silent un-reviewed PR). First run: **PASS — 7/7 checks, 0 gaps**.
- **S5 opened (live)** — `bin/eval-drift.py` drift/L2 panel: the re-risk layer over the earlier
  fixes. Seven gold rows (S1 dual-mode · S1 session-retention · S3 orphan-indexed · S4 legacy-
  markers · S4 verdict-repair · S8 roster-closed · S9 key-advisory) each re-checked on the current
  state; `drift.json` accumulates first/last-verified so the trend "did earlier fixes stay good"
  survives re-runs. First run: **PASS — all 7 HOLD (0 drift)**. L2 is NOT liveness (S6 retracted):
  each row asserts a *fix invariant* against repo/stack state, not uptime.
- **S5 depth (gold-rows → 13)** — registered the S2 state-machine invariants + S4 P4 as drift rows
  so the post-pass green is itself re-verified run-over-run:
  - `s2-uat-gate-closed` — no complete task's PRD still queued (T2)
  - `s2-merge-approve` — merged task's last review is APPROVE (T4)
  - `s2-merged-complete` — merged task is complete (T5)
  - `s4-report-body-fidelity` — final review verdict equals report body (P4)
  All 13 HOLD. Detection validated by simulated injection (corrupt verdict → s2-merge-approve
  DRIFT; corrupt report body → s4-report-body DRIFT; restore → clear).
- **S6–S9 added** — new breadth beyond the original five, each choosing a concrete factory invariant.
- **S6 retracted** — liveness/uptime is ops monitoring, not eval (an eval row must assert an
  invariant against a decision; dual-mode fidelity is already S1's claim).
- **S8 + S9 opened (live)** — `bin/eval-hygiene.py` deterministic panel:
  - S8 roster-completeness → **FAIL first run**: prd-reviewer had a persona but no
    run-contract skill and no artifact map. **Fixed** (same session): created
    `.agents/skills/prd-reviewer-ops/SKILL.md` + `docs/reference/prd-reviewer-agent.md`
    (lighter, honest to its in-session shape — no host driver by design).
    Re-run: **PASS** — all four roster agents have complete triads.
  - S9 repo-hygiene → langfuse keys (`sk-lf-…`/`pk-lf-…`) in a tracked session
    transcript; **reclassified as accepted-risk advisory** (local-only instance,
    2026-08-20) — rotate only if ever network-exposed. Other checks PASS.
- **S10** registered as the deferred app gate (the moment app preflights clear, these open).
- **S7 opened (live)** — the decision-03 headline surface: `bin/eval-context.py` grades the factory's
  own context engine (progressive-disclosure spine AGENTS.md → factory-context.md → discovery layer
  → knowledge base). C1 footprint/leanness (AGENTS.md 579 tok, factory-context 3,031 tok — within
  budgets; persistent `context.json` flags >2× growth) · C2 retrieval reachability (spine-doc link
  integrity, GFM-anchor aware) · C3 summary fidelity (five components claim, roster table ↔ agent
  files, vision links, ~2,500-tok initial-footprint claim). **First run FAIL**: 2 broken openwiki
  links in factory-context.md (missing `../` prefix) → **fixed** → re-run **PASS**. Both fixes
  registered as drift gold rows (s7-spine-links, s7-footprint).
- Decision 03 recorded: eval signal feeds the **context engine** — so S7 (engine-surface) is named
  **the** headline surface, matching the mission.
- **S1 depth-first pass #1 (SKIP-shrink)** — expanded the curated claim table from 23 → 63 checks
  (two new tranches: factory-process invariants + app/component artifacts). SKIP 98 → **58**,
  PASS 22 → **62**, FAIL 0. Every new claim verified against a real artifact (script, skill,
  config, dir); one mis-targeted claim (task-similarity policy lives in the product-layer skill,
  not a bin tool) corrected in-pass. The decision-03 metric "SKIP fraction shrinks as the engine
  feeds more decisions checkably" moved 98/120 → 58/120.
- **S2 upgraded gaps-only → PASS/FAIL state-machine panel** — `eval-pipeline.py` now grades the
  lifecycle machine (in-prd → prd-ready → in-progress → in-review → complete) with six checks:
  T1 state-legal · T2 complete→PRD-archived (UAT gate) · T3 complete+PR→impl/rev evidence ·
  T4 merged→APPROVE · T5 merged→complete · T6 queue-gate. First run: **18 PASS / 0 FAIL / 8 SKIP**
  — the 8 SKIPs are zero-evidence legacy completions (no PRD/impl/rev anywhere; honestly
  unverifiable, not failed). All 8 merged tasks have APPROVE + complete; the 4 pre-PR-era tasks
  with archived PRDs PASS on T1+T2; post-PR-era tasks get the full chain.
- **S1 depth-first pass #2 (SKIP-shrink 58 → 21)** — added the legacy app/CI/gdrive tranche
  (workspace-portability device-auth + parallel-clone, feed_analyser agent-service/FTS5/capture,
  CI workflow seams, gdrive PRD-backlog, repo-privacy via `gh api`, review read-only git, manual
  fallback, loop-end invariant). PASS 62 → **99**, SKIP 58 → **21**, FAIL 0. Honesty: two
  mis-targeted claims caught (task-similarity policy lives in the product-layer skill;
  incremental-write is a behavioral convention with no repo artifact → honestly SKIP). The 21
  remaining SKIPs are all behavioral/deferred/ambiguous decisions — non-checkable, never forced.

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