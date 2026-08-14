# Implementer Revision Brief

- **PR**: ak47-arch/workspace#2 (same branch: factory/implementer-ponytail/20260814-212431)
- **Task slug**: implementer-ponytail
- **PRD path** (read-only; also below): /home/anupam/Desktop/workspace/docs/prd-queue/2026-08-14-implementer-ponytail.md
- **Impl session UUID** (reused from the original run, decision 08): 8483b243-ad9a-4e00-be82-0cdf26a8801d
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
