## Decision: PRD status lifecycle — Final when the review gate passes

**Status**: accepted
**Date**: 2026-08-09 21:18
**Task**: extension-inline-agent
**Project**: software-factory
**Session**: sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/session.jsonl

### Context

PRDs carry their own `**Status**` header field whose vocabulary (per the
product-layer skill) is `Draft | Review | Final`. In practice the vocabulary
had never been exercised: every PRD in the queue and archive still sat at
`Draft`, and the archive policy for completed PRDs was silent on the field.
The first prd-reviewer-gated PRD (extension-inline-agent) was the first time
a document actually traversed the states, so the promotion rule needed to be
settled.

### Problem

Ambiguous when a PRD legitimately becomes `Final`, and whether archived PRDs
(whose tasks are already `complete`) should be retroactively marked. Without
a rule, the header degrades into an untrusted field that nobody updates.

### Alternatives

- Keep `Review` forever and rely solely on the task lifecycle
  (`in-prd → prd-ready → in-progress → in-review → complete`). Rejected: the
  PRD status and the task status are two distinct vocabularies on purpose —
  the PRD's status reflects the document's own gate, not the task's.
- Add a fourth value `Ready`. Rejected: `Ready` is not in the skill's
  vocabulary; `Final` already means "reviewed and accepted as implementation
  authority".

### Decision

- A PRD moves `Review → Final` **when the prd-reviewer gate returns READY**
  (a NOT READY verdict keeps it at `Review` until the blocking findings are
  fixed and re-reviewed).
- Archived PRDs whose tasks are marked `complete` are promoted
  `Draft → Final` during finalisation — a completed task implicitly means its
  plan is final.
- A `Draft` PRD stays `Draft` until its task is picked up and planned
  (gdrive-instruction-source-ingest remains `Draft` — no task file exists).

### Rationale

The review gate is the single source of "this plan is settleable": READY is
machine-checked (deterministic + judgment checks), so promoting on it is
objective rather than a human whim. Retroactive promotion of archived PRDs
keeps the corpus honest with one pass instead of leaving half the archive at
a misleading `Draft` (in practice their statuses were never updated when the
tasks completed).

### Consequences

- `docs/prd-queue/2026-08-08-extension-inline-agent.md` was promoted to
  `Final` after the round-2 READY review; four archived PRDs
  (github-browser-auth-flow, x-capture-instrument, extend-software-factory-wsff,
  task-file-dashboard) were promoted during the same cleanup.
- Pairs with review evidence files under `docs/reviews/` — a `Final` PRD
  should be traceable to the review report that gated it.
- Future agents can trust the header: `Final` ⇒ gate passed or task complete.

### Revision triggers

- If the product-layer skill changes the status vocabulary (e.g. adds
  `Ready`/`Approved`), re-map the promotion rule.
- If prd-reviewer becomes advisory instead of a gate, promotion on READY no
  longer holds and the rule must be rethought.