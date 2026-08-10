## Decision: Sandbox built on workspace-portability — new profile, pi install in-scope, container definition in portability

**Status**: accepted
**Date**: 2026-08-10 20:59
**Task**: implementer-agent
**Project**: software-factory
**Session**: sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/session.jsonl

### Context

The workspace is moving its infra to the cloud; the implementer sandbox must not be a throwaway local hack. `workspace-portability/` already owns the environment lifecycle: a manifest (`workspace_restore_manifest.json` v3 — repos, host deps, setup steps, secrets), five machine profiles, a two-phase bootstrap (automatic code+data, then interactive setup), and a documented open item: pi installation was explicitly deferred ("Q8: pi global CLI installation — Deferred (out of scope)"). The user explicitly asked to integrate the sandbox with workspace-portability, and to restore only the minimum ("we need only the smallest restoration to keep things fast").

### Problem

How is the sandbox image defined and provisioned so that it reuses the factory's proven env-setup machinery, stays fast (no full restore), and is cloud-portable without duplicating state?

### Alternatives

- **Standalone Dockerfile in the workspace root** — rejected: bypasses the manifest/profiles/secrets machinery that already encodes the workspace.
- **Build-time clone of all repos into the image** — rejected: bakes a GitHub token into layers, goes stale, slow builds; contradicts the run-time provision model.
- **Bake portability tooling + profile in the image; restore repos at run time only where needed (chosen, refined by local bind-mount)** — the image is a thin runtime (node, pi, git, python, gh, portability scripts, pi base config with `defaultProjectTrust=always`); locally the driver bind-mounts host repos (no clone at all); cloud workers restore a minimal targeted repo set via the new profile into durable storage.

### Decision

- **Container definition lives in workspace-portability**: `container/Dockerfile`, `container/sandbox-entrypoint.sh`, `container/run-sandbox.sh` (host wrapper), plus a new **`profiles/factory-sandbox.conf`** (repos-only: workspace root + target repo; `RESTORE_CRITICAL=false`, `HYDRATE_ASSETS=false`, `MATERIALIZE_SECRETS=false`, `START_SERVICES=false`, `RUN_SETUP=minimal`).
- **Pi installation moves in-scope in portability** as a setup step (`setup_pi.py` following the existing per-repo pattern) — closing the deferred Q8 item with the sandbox as its first consumer.
- **Minimal restore**: `restore_workspace.py --repos` already supports targeted sets; the `factory-sandbox` profile uses it for cloud worker provisioning (workspace root + target repo via the PRD→manifest repo mapping; `additional_repos` only if a PRD explicitly needs one).
- **Locally, no cloning**: the driver bind-mounts the host's existing repos (host workspace ro at `/workspace`, run dir rw at `/sandbox`) — the smallest possible per-run footprint.
- **Repo layout**: portability owns the container/env capability; the workspace root owns the factory logic (driver, implementer agent, `implementer-ops` skill). The task's implementation therefore spans two repos (cross-repo PRs).

### Rationale

- Reuse beats re-implement: manifest, profiles, secrets strategy, and the "Phase 1 never fails for secrets" invariant all carry over.
- The same image + driver run locally (bind mounts) and in the cloud (portability restore into durable storage); only the workspace *source* differs.
- Keeping the container image thin means no stale repos, no secrets in layers, and rebuilds only on toolchain/config change.

### Consequences

- Cross-repo implementation: PRs into both `ak47-arch/workspace` and `ak47-arch/workspace-portability`.
- Portability plan/PRD docs must be updated: pi installation no longer deferred; new profile documented.
- The cloud worker story ("move infra to cloud") inherits the sandbox profile as its provisioning contract.

### Revision triggers

- The cloud migration lands a concrete runtime (k8s/ECS) — then the profile's "durable storage" mapping must be pinned to that runtime's volume model.
- Portability's manifest v4 changes the profile/secrets schema — the profile and entrypoint must follow.
- A repo becomes so large that per-run clone cost on cloud workers outweighs caching — revisit workspace-source strategy.