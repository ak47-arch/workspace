## Decision: Partial-split remainder registered as new pending task

**Status**: accepted
**Date**: 2026-08-16 23:49
**Task**: task-pickup-similarity-merge
**Project**: software-factory
**Session**: sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/session.jsonl

### Context

During a partial-similarity split (decision 02), the picked task is divided: the overlapping part joins the merge bundle, and a remainder is left over. The question is what happens to that remainder.

### Alternatives

- **Only note the remainder in the session** — rejected: the clarified remainder would be lost when the session ends; nothing ensures it is ever picked up.
- **Rewrite the original task line** — rejected: `docs/tasks.txt` preserves original task lines verbatim; clarity lives in the task file and PRD, not in rewritten list lines.
- **Register the remainder as a new pending line** — accepted.

### Decision

The agent registers the remainder as a **new line in `docs/tasks.txt`** under its project's Pending section, with the clarified wording, and **no slug** — it earns a slug when it is picked up later, like every other pending task. The current session proceeds with the merged bundle.

### Rationale

Writing the remainder back into the pool keeps the split visible and pickable in a later session — the clarification is preserved as a concrete task, not lost to the conversation. Existing task-file/tasks.txt conventions stay untouched: verbatim source lines, slug annotation at pick-up time.

### Consequences

- Partial splits produce a durable, clarified task entry for the leftover scope.
- The pool (`docs/tasks.txt`) grows by exactly one line per split; the dashboard picks it up automatically.
- The original picked task's line stays verbatim with the bundle slug annotated on it.

### Revision triggers

- If partial splits become frequent enough to fragment the pool, a threshold rule (e.g. only split when both parts are non-trivial) may be needed.
