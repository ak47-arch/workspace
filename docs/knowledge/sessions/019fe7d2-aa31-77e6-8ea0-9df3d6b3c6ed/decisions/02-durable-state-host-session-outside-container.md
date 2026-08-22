## Decision: Durable state lives on the host — session outside the container, docs read-only by mount

**Status**: accepted
**Date**: 2026-08-10 20:59
**Task**: [implementer-agent](../../../../tasks/implementer-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Worktree, session log, outbox, report, and decisions live on the host under ~/.factory/runs/<slug>-<ts>/ and docs/implementations/<date>-<slug>/; the container mounts the

### Context

The user's direct experience: agents inside ephemeral containers died "for no reason" and everything inside vanished. The managed-agents article's core invariant is that the session log (append-only record of everything that happened) lives outside the sandbox and is written durably as events are emitted; the sandbox holds only scratch. Additionally, the implemented agent had to be prevented from touching factory bookkeeping (`docs/tasks/`, `docs/tasks.txt`, `docs/prd-queue/`, `docs/knowledge/index.md`), and repository credentials must never reach untrusted generated code.

### Problem

Where do the worktree, session trace, run report, and decisions live so that a container death is survivable, and how are the boundary rules (no docs writes, no push) enforced — by prompt or by mechanism?

### Alternatives

- **Prompt-level rules** ("never touch docs", "never push") — rejected: unenforceable for an autonomous worker; drift is a matter of time.
- **Scrub GITHUB_TOKEN from the implementer env** — kept, but insufficient alone (the container still held the worktree and session).
- **Docs read-only by bind mount + no repo credentials in the container (chosen)** — `/workspace` is mounted ro so docs writes are physically impossible; the container env contains only LLM + Langfuse keys; the driver owns push/PR.

### Decision

- **Worktree, session log, outbox, report, and decisions live on the host** under `~/.factory/runs/<slug>-<ts>/` and `docs/implementations/<date>-<slug>/`; the container mounts them rw only at `/sandbox` (worktree + outbox).
- **The implementer's stdout event stream is captured live by the driver** into `docs/knowledge/sessions/<impl-uuid>/session.jsonl` (the durable session, written as events arrive — `emitEvent`-style, not batched at the end).
- **`/workspace` (host workspace: docs, PRDs, `.pi`, `.agents/skills`) is mounted read-only** — the implementer physically cannot modify factory bookkeeping; it can only read.
- **No GitHub token or host secrets enter the container** — repository pushes and PR creation are driver-only. The container env allowlist is LLM provider keys + Langfuse + model override.
- **Commit-early convention**: the implementer commits after each completed user story so a respawned container resumes from committed state.

### Rationale

- Mechanism > prompt for boundaries that are safety-relevant; the ro mount is the same reasoning as the review agent's read-only tool list, taken to the filesystem level.
- Survival without recovery logic: container death is a non-event for durable state; respawn re-mounts the same run dir.
- The host-side session log gives debugging a window in that the coupled design lacked (the article's exact critique).

### Consequences

- Knowledge capture becomes survivable by construction: the session evidence and decisions outbox are host-durable.
- Driver must implement live stream capture, liveness watch, and a bounded respawn policy (default 3).
- Container image stays small (no repo data baked) and rebuilds are rare.

### Revision triggers

- A task genuinely requires container-persistent state across the run (e.g. long builds) — then that state must be explicitly named and backed up, not assumed.
- Secrets must enter the container for a tool (e.g. a third-party service used by the implementation) — then scoped token handling per the article's vault/proxy patterns is required before inclusion.
