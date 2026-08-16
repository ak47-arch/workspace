# Code Review Task Brief

- **PR URL**: ak47-arch/workspace#4
- **Task slug**: ponytail-skills-fixed-mount
- **PRD path** (read-only; also below): /home/anupam/Desktop/workspace/docs/prd-queue/2026-08-16-ponytail-skills-fixed-mount.md
- **Review session UUID**: 0bb584c8-f18c-4655-97b9-bc100c39a087
- **Worktree path** (PR head, read-only for you): /sandbox/worktree
- **Base ref**: 85a6c4b08e40fab84a25b0a4735abe66620eaac6
- **Head ref**: a2c1b8906af5503b2da4034cb0f5bfbab8af1dc7
- **Outbox path** (write the review report here): /sandbox/outbox

## Rules (binding)

1. You are the READ-ONLY reviewer. You never write to the target repo, never
   commit, and never mutate git state in /sandbox/worktree.
2. Read-only git IS allowed (git diff/log/show/status) — you need it to review
   base...head — but never add/commit/push/checkout/reset/stash.
3. NEVER run 'gh'. Every GitHub call is driver-side. No GitHub credential
   exists in this container.
4. Do NOT modify docs/tasks/, docs/tasks.txt, docs/prd-queue/, or the knowledge
   index. Do NOT write secrets anywhere.
5. Follow the review-ops skill for the check classes + report schema.

## Verification

See the PRD '## Testing decisions' for the acceptance commands. Run them inside the worktree as the PRD specifies; record exactly what runs and what is deferred.
- State evidence for each check/story (what you ran and how it passed/failed).

## Completion

Write /sandbox/outbox/report.md (per-story + per-check PASS/FAIL with evidence,
blocking vs advisory findings, verdict APPROVE|REQUEST_CHANGES, UAT hand-off
list) and any emerged decisions to /sandbox/outbox/decisions/NN-<slug>.md, then
exit 0. On partial review, still write the report and exit 1.
