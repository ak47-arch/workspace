## Decision: Implementer as host harness + cattle container (brain/hands decoupling)

**Status**: accepted
**Date**: 2026-08-10 20:59
**Task**: [implementer-agent](../../../../tasks/implementer-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Two-part split following Anthropic's managed-agents pattern: the host-side driver (bin/implementer-run.sh) is the harness — it picks the PRD, creates a host-side git work

### Context

The factory's assembly line was planned to include an autonomous implementation agent (deferred in `03-scope-boundary-ci-and-implementer-deferred-to-part2`). Grilling the "Build the implementer agent" task, the first design was "everything inside a one-shot container": driver, worktree, session, and reports all in an ephemeral `podman run`. The user pushed to read Anthropic's managed-agents engineering, which describes exactly the failure this workspace had already lived through: "containers suddenly go down for no reason and so does everything inside them". The article's fix is decoupling the harness ("brain") from the sandbox ("hands") — containers become cattle, re-initialized by a provision recipe; the session log lives outside the container.

### Problem

How to run an autonomous implementer reliably when the execution runtime is an ephemeral container that can die at any moment — without losing the work, the reasoning trail, or the ability to resume?

### Alternatives

- **Everything inside one container (original v1)** — accepted in Q3, then revised. Rejected as final: a container death loses worktree + session + report with no recovery path; debugging a stuck container has no window in.
- **Persistent sandbox container (reused state across runs)** — rejected: stateful, needs volume/session management, harder to migrate to the cloud.
- **Host harness + cattle container (chosen)** — the driver (deterministic orchestration, all git mutations) lives on the host; the container runs only the headless implementer pi process against bind-mounted durable state.

### Decision

Two-part split following Anthropic's managed-agents pattern: the **host-side driver** (bin/implementer-run.sh) is the harness — it picks the PRD, creates a host-side git worktree, writes the brief, provisions the container, streams the implementer's events to a host session log live, watches liveness and **respawns** on abnormal death, and owns push/PR/lifecycle commits. The **container is cattle** — one headless `pi` process, provisioned per run from the sandbox image with mounts (`/workspace` ro, `/sandbox` rw), killed and respawned freely.

### Rationale

- Directly contains the observed failure mode: container death loses only the pi process; every durable artifact is host-side.
- The decoupled shape is cloud-native: stateless jobs, provision recipe, durable volumes — the same image/driver later run on a cloud scheduler.
- Matches pi's "Plain Docker" containerization pattern and reuses the existing subagent/pi headless invocation (`pi --mode json --no-session -p`).

### Consequences

- Driver owns all git mutations and GitHub credentials; the container never holds repo secrets (mechanism-level no-push).
- Implementer commits early and often (per user story) so resume from a respawned container is natural.
- The session stream is the durable reasoning trail, written as events arrive (not at the end).
- Local runs use bind-mounted host repos (no cloning); cloud workers provision their durable workspace via portability.

### Revision triggers

- A persistent-state model becomes necessary (e.g. the implementer needs long-lived caches that survive within one run).
- The host becomes unavailable/unreliable and the harness itself must move into the cloud runtime (then driver + container move together, keeping the same separation).
- pi ships a managed/hosted agent primitive that supersedes the custom harness.
