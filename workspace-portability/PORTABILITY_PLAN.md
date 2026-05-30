# Workspace Portability Status

## North star

From a fresh Linux machine, we can run deterministic scripts that:

1. prepare the host
2. restore all workspace repos on the correct branches
3. restore critical local-only state
4. restore large assets
5. materialize required secrets/config
6. install repo dependencies
7. start canonical runtime services
8. verify the end state

## Implemented

### Phase 1 — Canonical standalone bundle

Implemented under `workspace-portability/`:

- `bootstrap-host.sh`
- `create-snapshot.sh`
- `create-large-assets-snapshot.sh`
- `create-all-snapshots.sh`
- `restore-workspace.sh`
- `materialize-secrets.sh`
- `hydrate-large-assets.sh`
- `setup-workspace.sh`
- `start-services.sh`
- `verify-workspace.sh`
- `full-restore.sh`
- `test-restore.sh`

### Phase 2 — Environment rebuild

Implemented via manifest-driven `setup_steps` and `setup-workspace.sh`.

Current steps cover:

- `agent-browser` pnpm deps
- `feed_analyser` backend/frontend deps
- `hermes` Python + Node deps
- `llm` Python deps
- `pi-mono` npm deps
- `survival-infrastructure` Python deps

### Phase 3 — Service startup orchestration

Implemented via `start-services.sh`.

Current canonical runtime targets:

- `app-dev`
- `app-prod`
- `app-prod-copy`
- `hermes`
- `llm`

Startup uses `survival-infrastructure/start_stack.sh` and manifest-defined health checks.

### Phase 4 — Secrets hardening

Implemented via:

- `materialize-secrets.sh`
- optional `age` encryption for offsite snapshot uploads
- restore support for `.tar.gz.age` artifacts

### Phase 5 — Large asset hydration

Implemented via:

- `create-large-assets-snapshot.sh`
- `hydrate-large-assets.sh`

Current large assets:

- `llm/gemma`
- `survival-infrastructure/llm/gemma`

### Phase 6 — Restore drills

Implemented via:

- `test-restore.sh`

This runs a scratch restore using the latest local artifacts.

## Remaining limitations

The bundle is now end-to-end, but a few operational assumptions remain:

- Docker is the current canonical runtime backend because `survival-infrastructure/start_stack.sh` uses `docker` / `docker-compose`.
- Startup still depends on valid `LLAMA_CPP_DIR` / `SURVIVAL_LLAMA_CPP_DIR` values.
- The setup step list is deterministic, but it is not yet exhaustive for every optional subproject or every nested package inside large monorepos.
- Offsite encryption is opt-in rather than default to preserve backward compatibility with existing plain artifacts.

## Recommended next hardening work

- make encrypted upload the default once age recipients are standardized
- add CI or VM-based `test-restore.sh` drills
- add more repo-specific setup steps if additional subprojects become required for runtime
- optionally add secret-manager integration in front of or instead of `--secrets-dir`
