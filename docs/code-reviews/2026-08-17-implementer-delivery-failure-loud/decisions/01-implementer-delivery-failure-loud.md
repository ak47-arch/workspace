# Decision: report/decision records must match the delivered diff (review finding)

- **Status**: proposed (review finding — driver decides follow-up)
- **Date**: 2026-08-17
- **Task**: implementer-delivery-failure-loud
- **Review session UUID**: 06b04dee-2555-4b08-b458-7792eb9aeb7b

## Context

Reviewing PR ak47-arch/workspace#10, the code is functionally correct and all four
user stories are verified green (72 passed, 0 failed), but the archived implementer
report + decision records do not match the shipped diff:

- `decisions/01-delivery-failure-loud-gh-seam.md` and `report.md` claim
  `bin/implementer-run.sh` `push_and_pr` was switched to the
  `gh_call`/`IMPLEMENTER_GH_BIN` seam (`gh_call pr create`,
  `command -v "${IMPLEMENTER_GH_BIN:-gh}"`, `gh_call label create`). The diff shows
  `push_and_pr` is unchanged from base — it still calls raw `command -v gh`,
  `gh label create`, and `gh pr create`. The pr-fail test actually mocks `gh` on
  `PATH`, which decision 01 explicitly rejects (option B).
- `decisions/02-delivery-failure-loud-local-nounset.md` describes adding
  `local pr_url=""`; base already shipped `local attempt=0 pr_url=""`.

## Decision

Treat the report/decision mismatch as a blocking (D7/J2) delivery-integrity finding.
Before the PR is accepted, align the archived records with the actual diff — either
(a) implement the claimed `gh_call`/`IMPLEMENTER_GH_BIN` seam in `push_and_pr`, or
(b) truthfully document that the tests mock `gh` on `PATH` and why that was chosen
over the PRD's stated seam — and correct the `local pr_url` claim in decision 02
(and the report's "71 passed" → actual 72). Copy the correction to the
`docs/knowledge/sessions/…` decision copies.

## Consequences

- Prevents a false mechanism from being baked into the knowledge base for the
  safety-critical delivery path (the very defect class this PRD addresses).
- No runtime code change is required for correctness (all stories verified); this
  is a documentation-alignment correction.
