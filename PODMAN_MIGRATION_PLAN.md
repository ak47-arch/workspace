# Docker → Podman Migration Plan

Last updated: 2026-05-28

## Goal

Migrate the workspace containerized applications from Docker-first operation to Podman-first operation with the smallest practical amount of application churn, while preserving current local-dev workflows.

## Scope

Applications reviewed in this workspace:

- `survival-infrastructure/`
- `llm/`
- `hermes/`
- `feed_analyser/`

Key files reviewed:

- `survival-infrastructure/docker-compose.yml`
- `survival-infrastructure/start_stack.sh`
- `llm/docker-compose.yml`
- `llm/scripts/compose_env_preflight.sh`
- `hermes/docker-compose.yml`
- `feed_analyser/docker-compose.yml`
- `feed_analyser/README.md`

## Current State Summary

### Runtime state observed

Currently running under Docker:

- `survival-app-dev`
- `llm-inference-server`

Currently running under Podman:

- none

### Tooling state observed

- Docker installed: `Docker version 29.1.3`
- Podman installed: `podman version 4.9.3`
- `podman compose` currently delegates to external provider `/home/anupam/.local/bin/docker-compose`

That last point matters: in the current environment, `podman compose` is **not yet a true Docker-free compose path**. Fixing that is phase 0.

## Assumptions

1. Primary target environment is Linux.
2. We want to preserve compose-based local development rather than rewrite everything into raw `podman run` / quadlet units immediately.
3. We do **not** want a big-bang migration; we want app-by-app cutover with rollback.
4. Short-term compatibility is more important than perfect Podman-native purity.
5. Existing named ports, bind mounts, and persisted data directories must keep working.

If any of these are wrong, adjust the plan before execution.

## Recommended Strategy

Use a **two-step migration model**:

1. **Compatibility-first**: get each app running on Podman with minimal code/config changes.
2. **Podman-native cleanup**: remove Docker-specific assumptions and replace them with Podman-safe patterns.

This avoids rewriting all startup scripts and compose files at once.

## Executive Recommendation

### Migrate in this order

1. `llm/`
2. `survival-infrastructure/`
3. `hermes/`
4. `feed_analyser/`

### Why this order

- `llm/` is the smallest, cleanest standalone service and is already health-checked.
- `survival-infrastructure/` depends operationally on the LLM and has a Docker-specific startup script.
- `hermes/` is simple but uses `network_mode: host`, which needs explicit Podman validation.
- `feed_analyser/` is highest risk because it mounts `/var/run/docker.sock`, uses Docker-oriented monitoring, and describes runner-container management from inside the backend.

## Application Inventory and Risk Assessment

## 1. `llm/`

### Current Docker-specific assumptions

- Uses `docker-compose.yml`
- Uses external network `workspace-shared-llm-network`
- Mounts host llama.cpp directory via `LLAMA_CPP_DIR`
- Documentation is Docker-first

### Risk

**Low**

### Main migration concerns

- Compose provider must work with Podman without falling back to Docker.
- External shared network creation must be done with `podman network create`.
- Need to verify mounted llama.cpp binaries work unchanged inside Podman containers.

### Acceptance criteria

- Container starts under Podman
- `GET /health` returns 200
- `GET /ready` returns 200
- Model mounts resolve correctly
- Shared network is usable by other apps

## 2. `survival-infrastructure/`

### Current Docker-specific assumptions

In `survival-infrastructure/start_stack.sh`:

- `docker network inspect/create`
- `docker ps`
- `docker inspect`
- `docker-compose up -d --build`
- Docker-specific running-container reporting

In `survival-infrastructure/docker-compose.yml`:

- `extra_hosts: host.docker.internal:host-gateway`
- external network `workspace-shared-llm-network`
- optional local `llm` profile

### Risk

**Medium**

### Main migration concerns

- `host.docker.internal:host-gateway` is Docker-oriented and should not remain the default Podman path.
- The canonical startup script is hard-coded to Docker CLI usage.
- Need to preserve the current behavior where the standalone `llm` container is ensured first.

### Acceptance criteria

- `app-dev` starts from a Podman-backed startup script
- startup script can create/inspect the shared network without Docker
- `GET /` and `GET /api/captures` on port `5151` succeed
- LLM dependency resolution works without relying on Docker-only host aliases

## 3. `hermes/`

### Current Docker-specific assumptions

- `docker-compose.yml` usage in comments/docs
- `network_mode: host`
- bind mount of `~/.hermes:/opt/data`
- UID/GID remapping assumptions

### Risk

**Medium**

### Main migration concerns

- Need to validate `network_mode: host` behavior under the chosen Podman mode.
- Rootless Podman networking behavior must be verified before declaring success.
- Need to confirm file ownership behavior remains correct with the UID/GID mapping workflow.

### Acceptance criteria

- `gateway` starts under Podman
- `dashboard` starts under Podman
- host-bound networking behavior matches current expectations
- files created in `~/.hermes` remain readable/writable by the host user

## 4. `feed_analyser/`

### Current Docker-specific assumptions

In `feed_analyser/docker-compose.yml`:

- `/var/run/docker.sock:/var/run/docker.sock`
- Dozzle configured as a Docker log viewer
- backend comment says it manages runner containers through Docker socket
- warm `runner-sandbox` container
- multiple bridge networks including an internal sandbox network

### Risk

**High**

### Main migration concerns

- `/var/run/docker.sock` must become either a Podman socket mount or be removed by redesign.
- If the backend actually creates/manages sibling containers, that logic must be tested against the Podman API/CLI.
- Dozzle may need replacement or reconfiguration.
- Internal sandbox network isolation must be retested under Podman networking.

### Acceptance criteria

- backend, watcher, frontend, and sandbox start under Podman
- backend can still perform any required sandbox-container orchestration
- log-viewing solution still works or is replaced with an agreed alternative
- sandbox network remains isolated from the internet as intended

## Phase Plan

## Phase 0 — Prerequisites and Baseline

### Objective

Make the environment capable of running Podman compose workloads without secretly relying on Docker.

### Tasks

1. Decide the compose provider strategy.
   - Preferred: install/configure `podman-compose` or another Podman-capable compose provider.
   - Avoid leaving `podman compose` delegated to Docker Compose if the goal is full Docker removal.
2. Enable and verify the Podman socket if any app needs Docker-socket-style API access.
3. Decide whether to use:
   - `podman-docker` compatibility package for a transitional `docker` CLI shim, or
   - explicit script updates to `podman` commands.
4. Capture baseline behavior under Docker:
   - startup commands
   - port mappings
   - health endpoints
   - volume locations
   - network names
5. Record rollback commands for each app.

### Deliverables

- confirmed compose provider choice
- confirmed Podman socket strategy
- baseline checklist per app

### Exit criteria

- `podman compose` path does not depend on Docker unless explicitly accepted as temporary
- Podman can build and start a trivial compose service in this environment

## Phase 1 — Migrate `llm/`

### Objective

Establish the shared Podman network and prove the simplest production-like service works first.

### Tasks

1. Create Podman equivalent of `workspace-shared-llm-network`.
2. Run `llm/` with Podman compose.
3. Verify mounts:
   - `./gemma:/models:ro`
   - `${LLAMA_CPP_DIR}:/opt/llama-cpp:ro`
4. Verify health and readiness checks.
5. Update `llm/README.md` with Podman-first or dual-runtime instructions after validation.

### Exit criteria

- `llm-inference-server` runs under Podman
- other containers can reach it on the shared network

## Phase 2 — Migrate `survival-infrastructure/`

### Objective

Replace Docker-hardcoded orchestration with runtime-agnostic or Podman-native orchestration.

### Tasks

1. Refactor `survival-infrastructure/start_stack.sh`:
   - parameterize container runtime (`docker` vs `podman`) during transition, or
   - switch fully to Podman after validation.
2. Replace network management commands with runtime-aware equivalents.
3. Replace container inspection and process checks with runtime-aware equivalents.
4. Remove Docker-specific default dependency on `host.docker.internal` where feasible.
   - Prefer service-to-service networking on `workspace-shared-llm-network`.
   - Use `host.containers.internal` only when host access is actually required.
5. Validate `app-dev`, then `app-prod`, then `app-prod-copy`.
6. Update the skill/runtime docs after the script is changed.

### Exit criteria

- default startup path works with Podman
- app containers reach LLM reliably
- no Docker-only command remains in the critical startup path

## Phase 3 — Migrate `hermes/`

### Objective

Prove host-network and persistent-user-data workflows under Podman.

### Tasks

1. Run Hermes under Podman using the existing compose definition if possible.
2. Validate `network_mode: host` behavior.
3. If host networking is unreliable under the chosen Podman mode, switch to explicit port bindings.
4. Validate `~/.hermes` permissions with `HERMES_UID` / `HERMES_GID`.
5. Update `hermes/docker-compose.yml` comments/docs if any Podman-specific caveats are needed.

### Exit criteria

- Hermes gateway and dashboard both run correctly under Podman
- no file permission regression in `~/.hermes`

## Phase 4 — Migrate `feed_analyser/`

### Objective

Handle the highest-risk app last, after Podman networking and compose patterns are proven elsewhere.

### Tasks

1. Confirm whether backend truly requires container orchestration via socket.
   - If no: remove the socket mount.
   - If yes: switch to Podman socket compatibility and test the backend behavior explicitly.
2. Replace or reconfigure Dozzle.
   - Option A: validate Dozzle against Podman-compatible socket access.
   - Option B: replace with a Podman-friendly log workflow.
3. Validate `app-net` and `sandbox-net` behavior under Podman.
4. Verify internal network isolation still blocks outbound internet from the sandbox.
5. Verify warm sandbox container approach still behaves as intended.
6. Update `feed_analyser/README.md` to remove Docker-only setup steps.

### Exit criteria

- full stack starts on Podman
- backend sandbox workflow still works
- monitoring/logging approach is agreed and documented

## Cross-Cutting Technical Changes

## 1. Compose command standardization

### During transition

Support both runtimes explicitly:

- `docker compose ...`
- `podman compose ...`

### End state

Standardize on one Podman-backed command path.

Recommended end-state options:

- **Option A: explicit Podman** — clearest and least ambiguous
- **Option B: `podman-docker` shim** — lower script churn, but more hidden magic

Recommendation: use **explicit Podman in scripts**, and keep shims only as short-term compatibility helpers.

## 2. Networking cleanup

Standardize these patterns:

- shared inter-app network: `workspace-shared-llm-network`
- avoid Docker-only host aliases where service discovery can be used instead
- document any required Podman rootless networking caveats

## 3. Socket usage cleanup

Audit every use of:

- `/var/run/docker.sock`
- Docker CLI subprocesses
- Docker-specific API assumptions

Target hierarchy:

1. remove need for socket access where possible
2. if still required, use Podman socket explicitly
3. document the security implications

## 4. Documentation cleanup

Update app READMEs and scripts so the docs match the actual runtime.

Minimum doc updates:

- startup commands
- prerequisite installs
- network creation commands
- host alias caveats
- rollback instructions

## Test Matrix

## Global checks

For each migrated app:

- image builds under Podman
- container starts cleanly
- expected ports are reachable
- logs show no runtime-specific errors
- bind-mounted data persists across restart
- named/external networks behave as expected

## App-specific checks

### `llm/`

- `/health`
- `/ready`
- model list endpoint
- inference request smoke test

### `survival-infrastructure/`

- `/`
- `/api/captures`
- capture write persists to mounted data dir
- app reaches LLM over the intended network path

### `hermes/`

- gateway process stays up
- dashboard reachable on expected host interface
- writes to `~/.hermes` preserve host ownership expectations

### `feed_analyser/`

- frontend reachable on `5174`
- backend reachable on `8000`
- watcher stays healthy
- sandbox isolation verified
- log viewer replacement/compatibility verified

## Rollback Plan

Keep rollback simple and per-app.

For each app migration wave:

1. stop Podman stack
2. restart prior Docker stack using the last known-good command
3. verify original health endpoints
4. do not delete existing bind-mounted data or named volumes until Podman path is proven stable

Important: do not remove Docker assets globally until all four apps have passed acceptance criteria.

## Suggested Delivery Schedule

## Wave 1

- Phase 0
- Phase 1 (`llm/`)

## Wave 2

- Phase 2 (`survival-infrastructure/`)

## Wave 3

- Phase 3 (`hermes/`)

## Wave 4

- Phase 4 (`feed_analyser/`)

## Definition of Done

The migration is complete when all of the following are true:

1. All in-scope apps can be built and started with Podman.
2. No critical runtime path depends on Docker daemon availability.
3. Shared networking between `llm/` and `survival-infrastructure/` works under Podman.
4. Persistent volumes and bind-mounted app data survive restart without ownership regressions.
5. App docs and startup scripts reflect the Podman path.
6. Docker is optional fallback only, not a hidden dependency.

## Immediate Next Actions

1. Fix phase 0 first: make `podman compose` stop delegating to Docker if full migration is the goal.
2. Run the first pilot on `llm/`.
3. After `llm/` passes, update `survival-infrastructure/start_stack.sh` to support Podman.
4. Leave `feed_analyser/` for last because socket/orchestration behavior is the biggest unknown.
