# Implementer Revision Brief

- **PR**: ak47-arch/workspace#12 (same branch: factory/multi-repo-delivery-bookkeeping-prs/20260819-013447)
- **Task slug**: multi-repo-delivery-bookkeeping-prs
- **PRD path** (read-only; also below): /home/anupam/.herdr/worktrees/workspace/factory-local-run-multi-repo-20260819-013126/docs/prd-queue/2026-08-18-multi-repo-delivery-bookkeeping-prs.md
- **Impl session UUID** (reused from the original run, decision 08): 4d89a859-9d05-4b28-9efd-e56aad8837e7
- **Original review (BINDING authority)**: /sandbox/review/report.md + /sandbox/review/decisions/
- **Worktree path** (same branch, read-write): /sandbox/worktree
- **Outbox path** (write results here): /sandbox/outbox

## Rules (binding)

1. Fix EXACTLY what the review findings scope — no more, no less. No scope expansion.
2. WHERE THE REVIEW FINDINGS CONFLICT WITH YOUR EARLIER REASONING, THE FINDINGS WIN.
   The review report + decisions are higher-priority authority than your prior reasoning.
3. Resume your original implementation session context (continuity) — do NOT
   restart from scratch, do NOT re-litigate findings.
4. Do NOT run any git commands (the host owns git). Do NOT change the task
   lifecycle — the task stays in-review through the re-review.
5. Do NOT write secrets, keys, or GitHub credentials anywhere.

## Verification

See the PRD `## Testing decisions` for the acceptance commands. Run them inside the worktree as the PRD specifies.
- State evidence for each story (what you changed and how it is verified).

## Completion

Write /sandbox/outbox/report.md (per-story done/not-done + evidence +
verification results + UAT hand-off list) and any emerged decisions to
/sandbox/outbox/decisions/NN-<slug>.md (structured decision format), then exit 0.
On partial failure, still write the report and exit 1.
