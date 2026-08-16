# Implementer Task Brief

- **PRD path**: /home/anupam/Desktop/workspace/docs/prd-queue/2026-08-17-headless-agent-containerisation.md (read-only; also below)
- **Task slug**: headless-agent-containerisation
- **Impl session UUID**: 771b4017-a17d-4464-9896-476407652701
- **Worktree path** (read-write; your working directory): /sandbox/worktree
- **Outbox path** (write results here): /sandbox/outbox

## Rules (binding)

1. Implement EVERY user story in the PRD, one story/unit at a time.
2. Work ONLY inside /sandbox/worktree. Your edits are already durable on the
   host's disk via this mount — you do NOT need to commit anything.
3. Do NOT run ANY git command (no init/add/commit/stash/push/pull/checkout).
   The host driver performs the single commit, push, and PR at the end.
4. You CANNOT modify docs/tasks/, docs/tasks.txt, or docs/prd-queue/ — those
   live in the read-only /workspace mount. Do not attempt to bypass this.
5. Do NOT write secrets, keys, or GitHub credentials anywhere.
6. Do NOT run builds that require network secrets you don't have.

## Verification

See the PRD  for the acceptance commands. Run them inside the worktree as the PRD specifies.
- State evidence for each story (what you changed and how it is verified).

## Completion

Write /sandbox/outbox/report.md (per-story done/not-done + evidence +
verification results + UAT hand-off list) and any emerged decisions to
/sandbox/outbox/decisions/NN-<slug>.md (structured decision format), then exit 0.
On partial failure, still write the report and exit 1.
