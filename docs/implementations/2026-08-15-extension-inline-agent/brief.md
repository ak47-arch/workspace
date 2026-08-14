# Implementer Revision Brief

- **PR**: ak47-arch/feed_analyser#1 (same branch: factory/extension-inline-agent/20260812-033024)
- **Task slug**: extension-inline-agent
- **PRD path** (read-only; also below): /home/anupam/Desktop/workspace/docs/prd-queue/2026-08-08-extension-inline-agent.md
- **Impl session UUID** (reused from the original run, decision 08): 60c0c537-b9c7-4c4c-8b8a-0be438950151
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
