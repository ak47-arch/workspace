# Implementer Report — typed-trail-integrity

- **Task**: typed-trail-integrity
- **Session UUID**: 05f805ea-0bae-44f3-9791-93fc9cb43639
- **PRD**: `docs/prd/2026-08-22-typed-trail-integrity.md`

## Summary

Made the disclosure trail machine-followable by construction. Three linked
changes (`docs/prd/` stable home + routing manifest, typed-link trail,
decision read-skip summaries) plus the S10 hygiene panel and S10 drift-gold
rows. Every user story is implemented and the acceptance gate (normative
counts + falsifiable injection flips) is verified inside the sandbox.

## Per-story status + evidence

### Story 1 — implementer: Final PRD cites governing decisions as typed links — **DONE**
- PRD front-matter is signed to typed relative links per Q3:
  `docs/prd/*.md` → `**Task**: [<slug>](../tasks/<slug>.md)`,
  `**Session**: [session.jsonl](../knowledge/sessions/<uuid>/session.jsonl)`,
  `**Decisions**: - [<title>](../knowledge/sessions/<uuid>/decisions/<file>.md)`,
  `**Status**: [<state>](./manifest.json)`.
- Evidence: head of `docs/prd/2026-08-22-typed-trail-integrity.md`:
  `**Task**: [typed-trail-integrity](../tasks/typed-trail-integrity.md)`,
  `**Session**: [session.jsonl](../knowledge/sessions/01a01a70-.../session.jsonl)`,
  two `**Decisions**:` typed links, `**Status**: [Final](./manifest.json)`.
  All decision/PRD relative links resolve to existing files (checked 0 broken).

### Story 2 — code-reviewer: PRD+task+knowledge trail resolves at every hop, stop early at summary — **DONE**
- Trail hops are typed relative links resolved from each file's own location.
  Verified every typed link in `docs/prd/*.md` and
  `docs/knowledge/**/decisions/*.md` resolves to an existing file.
- Decision read-skip summaries backfilled mechanically: **120/120** decision
  files now carry a `**Summary**:` line right after the metadata block
  (was 7/120).
  ✓ `bin/eval-hygiene.py` S10 summary check reports 120/120.

### Story 3 — context-engine owner: one hygiene panel fails on any non-machine-followable reference — **DONE**
- Extended `bin/eval-hygiene.py` with a new **S10 typed-trail-integrity**
  surface: (a) string-path refs, (b) decision `**Summary**:` present,
  (c) no stale/mismatched citations + manifest↔docs/prd coherence.
- Panel run: `S10 typed-trail: PASS` (0 string-path, 120/120 summaries,
  0 stale prd-queue/archive citations; manifest coherent).
- Falsifiable: `bin/test-typed-trail-integrity.{sh,py}` proves each check
  flips to FAIL under a mis-disclosure injection and PASSes on a clean
  fixture (no can't-fail rows).

### Story 4 — evaluator: register drift-gold rows — **DONE**
- Added three S10 drift-gold rows to `bin/eval-drift.py`
  (`s10-string-paths`, `s10-summaries`, `s10-stable-home`). A future
  disclosure-path regression flips them to DRIFT.
- Verified they HOLD (no S10 drift in `bin/eval-drift.py` run).

## Acceptance / verification results

1. **Normative goal**: `NO_LANGFUSE=1 python3 bin/eval-hygiene.py` →
   S10 string-path = **0**; S10 summaries = **120/120**;
   S10 stale/mismatch = **0**; manifest↔docs/prd coherent. (S8 PASS;
   S9 reports no branch-protection — environmental, see UAT.)
2. **Falsifiable proof (the gate)**: `bash bin/test-typed-trail-integrity.sh`
   → **PASS** — string-path, summary, and stale-check each flip to FAIL on
   injection; clean fixture green → no check is can't-fail.
3. **Single-transaction migration**: all 20 PRDs (4 queue + 16 archive)
   moved to `docs/prd/` in one pass; `docs/prd/manifest.json` created
   (20 rows: slug, file, status, ordering_key); deferred
   `docs/prd-queue/`/`docs/prd-archive/` retained as empty `.gitkeep`
   placeholders; every inbound live link fixed in the same pass
   (task files, `docs/reference/*`, `docs/factory-context.md`,
   `.pi/agents/*`, `docs/tasks/README.md`, decision-body stale citations).
4. **`--pick` ordering regression**: `bash bin/test-implementer-driver.sh`
   → **85 passed, 0 failed** — `resolve_prd() --pick` still selects the
   oldest Final+prd-ready PRD from the `docs/prd/` candidate set
   (longest-stable ordering_key preserved). `resolve_prd` globs
   `docs/prd/*.md` and reads `**Status**: [Final]` via a relaxed
   `\[?Final` grep so the typed Status link keeps the pick contract.

`bin/transition-task.sh` reworked: on `--to complete` it now flips the
manifest row `prds[].status → closed` instead of `mv`-ing the PRD
(no physical move — stable-home invariant). `bin/test-transition-task.sh`
→ **54 passed, 0 failed** (new `test_prd_manifest` covers it).

## UAT hand-off list
- **S9 branch-protection check** reports FAIL in the sandbox only because
  `gh`/GitHub are unreachable here (pre-existing environmental, not a
  regression). Re-run `bin/eval-hygiene.py` on a host with `gh` authed to
  confirm `PASS`.
- **Other pre-existing panel FAILs are environmental and unrelated**:
  `eval-context` vision links (gitignored cross-project dirs absent),
  `eval-decisions` 36 claim FAILs (cross-project code files not in this
  repo — e.g. `restore_workspace.py`), `eval-prd`. These predate this task.
- `docs/prd/manifest.json` statuses were seeded from each PRD's
  `**Status**:` (draft/final); `transition-task.sh --to complete` now flips
  to `closed` going forward. Confirm desired lifecycle values for the
  retired DSL.
- `bin/eval-context-semantic.py` still references `prd-queue/` in its
  resolver — that is the context-disclosure semantic-probe PRD's scope
  (separate task), not this one; left untouched per out-of-scope.
- The generated `docs/evaluations/2026-08-22-hygiene.{json,md}` and
  `2026-08-22-drift.{json,md}` are committed as fresh panel outputs.

## Decisions captured
- `decisions/01-typed-trail-check-scope-and-pick-contract.md` — scope of the
  string-path scan + the Status-link/pick-contract reconciliation.