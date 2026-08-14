## Decision: Task files carry a PR-tracking section — PR↔task↔review↔merge data is attached for retrospective evaluation

**Status**: accepted
**Date**: 2026-08-14
**Task**: code-review-agent
**Project**: software-factory
**Session**: sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl

### Context

During PR #1 reconciliation the user asked: "we need to attach PR data to tasks so
they can also be tracked … Everything can be tracked in retrospect. Complete
visibility and logging are prime requirements. We intend to run evaluations over
our data." Today the PR number/URL exists only in the implementer's run output and
the review archive; the task file carries no PR link, so a task cannot be traced
to its PR → review → merge without cross-referencing `docs/implementations/`,
`docs/code-reviews/`, and GitHub.

### Problem

Task ↔ PR ↔ review ↔ merge data lives in four separate places with no canonical
join key on the task itself. For retrospective evaluation (metrics over
implementer/review runs), the join must be reconstructible per task. It also must
survive: PRs get renumbered, branches get deleted, and runs get archived.

### Decision

Every task file (`docs/tasks/<slug>.md`) gains a **`## PR tracking`** section
appended/updated at each pipeline stage, populated in retrospect when a stage
happens without an automatable hook yet. Canonical schema:

```
## PR tracking
- PR: #<num> (<owner/repo>)
- URL: <full PR URL>
- Branch: factory/<slug>/<ts>
- Base: <branch> · Head: <sha> (raised <ts>)
- Raised by: implementer run <uuid>
- Review: <review session uuid> · verdict <APPROVE|REQUEST_CHANGES>
  · report docs/code-reviews/<date>-<slug>/
- Merge: <merge sha> (<ts>, by <actor>)  ·  (absent until merged)
```

The task `Status` remains the lifecycle source of truth; PR tracking is
append-only history. Example: `docs/tasks/code-review-agent.md`.

### Rationale

Single per-task join key; append-only so the audit trail never rewrites; cheap to
maintain manually until the drivers learn to write it (then it becomes a driver
responsibility — see revision triggers).

### Consequences

- `code-review-agent` task now carries its full PR trace; evaluators join on the
  task slug.
- Failed-run session traces (e.g. no-credential implementer attempt, first crashed
  review run) are committed to `docs/knowledge/sessions/` as evidence, not
  discarded — complete visibility.
- Later: the implementer/review drivers should append these lines automatically
  (raise → review → merge hooks), keeping the schema identical.

### Revision triggers

- The implementer driver learns to append the PR row on raise; the review driver
  on review; an operator script on merge — then manual appends stop.
- Evaluation tooling defines a stricter schema; migrate task files via a one-shot
  backfill (pattern exists: `bin/backfill-timestamps.sh`).