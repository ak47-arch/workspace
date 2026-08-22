## Decision: Implementer lifecycle & traceability — in-progress until merge, PRD stays queued, driver-shielded index

**Status**: accepted
**Date**: 2026-08-10 20:59
**Task**: [implementer-agent](../../../../tasks/implementer-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Lifecycle: driver runs bin/transition-task.sh <slug> --to in-progress at pickup (commit + push the workspace root).

### Context

The factory requires end-to-end traceability (task → PRD → implementation → verification) and maintains the invariant that a PRD leaves the queue only after UAT + user go-ahead. The user specified the task stays `in-progress` until the PR is merged, and wants the implementer to save knowledge (decisions) during implementation. `save-knowledge` finds the active session via `ls ~/.pi/agent/sessions` — blind for headless ephemeral runs. `docs/knowledge/index.md` is a hand-curated, script-sorted index.

### Problem

How does an autonomous implementer run update the task lifecycle without manual intervention, and how are its session trace and decisions captured durably and safely (given headless sessions have no discoverable session file, the container is ephemeral, and the curated index must not be corrupted)?

### Alternatives

- **No decisions from implementation (v1 earlier stance)** — rejected by the user: "i also would like to save knowledge."
- **Implementer writes directly into `docs/knowledge/index.md`** — rejected: the model would corrupt the hand-curated, sorted index.
- **Decisions-outbox + driver-shielded capture (chosen)** — the implementer writes candidate decision files into its outbox only; the driver archives them into the session's decisions dir and appends index entries deterministically via the existing `sort-knowledge-index.py` tooling.

### Decision

- **Lifecycle**: driver runs `bin/transition-task.sh <slug> --to in-progress` at pickup (commit + push the workspace root). The task **stays `in-progress` until the PR is merged**; the PRD stays in `docs/prd-queue/` throughout (existing archive gate). On failure, the driver transitions back to `prd-ready` (still pickable) and writes a partial report.
- **Session trace**: the driver captures the implementer's stdout JSONL stream live into `docs/knowledge/sessions/<impl-uuid>/session.jsonl` and links it on the task file — completing task→planning→implementation traceability.
- **Run report**: driver archives `outbox/report.md` + decisions into `docs/implementations/<date>-<slug>/` (committed) — per-story verification, UAT hand-off list, decisions-emerged.
- **Decision capture (`implementer-save`)**: the brief carries the impl session UUID; the implementer writes structured candidate decisions into its outbox only. The **driver** archives them into the session's decisions dir and appends index entries (`sort-knowledge-index.py`) — the model never touches `docs/knowledge/index.md`.

### Rationale

- Git is the only safe state exit for an ephemeral container; the driver's lifecycle commit ships task status, session link, and report together.
- Shielded index preserves the curated KB while still capturing implementation learnings on the spot.
- Sticking at `in-progress` until merge matches the existing "complete only after UAT + sign-off" invariant and keeps the PRD queue semantics coherent.

### Consequences

- `bin/transition-task.sh` gains a call site from the driver; dry-run of transitions covered by the existing test suite.
- New durable tree `docs/implementations/`; new `~/.factory/runs/` scratch tree.
- Implementation decisions enter the KB flagged as auto-captured; the review/merge stage re-curates before they're treated as durable.

### Revision triggers

- The review/merge stage lands and wants to own post-run curation — the driver's archive step may move behind it.
- `save-knowledge` gains an explicit-session-dir mode, making `implementer-save` redundant (collapse it).
- Task state semantics change (e.g. a distinct `in-review` meaning for PRs) — update the driver's transitions accordingly.
