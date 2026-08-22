## Decision: LLM credential resolution from pi's auth.json for sandboxed agents

**Status**: accepted
**Date**: 2026-08-17 01:41
**Task**: [sandbox-credential-mounting](../../../../tasks/sandbox-credential-mounting.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The driver's write_env_file() function, after forwarding allowlisted host env vars, also resolves credentials from ~/.pi/agent/auth.json for any allowlisted LLM provider

### Context

The factory's sandboxed agents (implementer, reviewer) run inside a container that requires `OPENROUTER_API_KEY` or `ANTHROPIC_API_KEY` in the environment. The host driver's `write_env_file()` function forwards only host env vars from the `env_allowlist`. However, pi on the host stores its OpenRouter key in `~/.pi/agent/auth.json` (under `openrouter.key`), not in the host environment — so the envfile was always empty of LLM credentials, causing every container to fail at boot with "no LLM credential".

### Problem

The sandboxed agents need LLM credentials to function, but the host driver only forwards env vars and pi never exports its key to the env. Adding a key export to the host's shell profile is fragile, user-hostile, and would leak the key to every child process on the host.

### Alternatives

- **Mount full auth.json into the container** — rejected: contains `github-copilot.access` token (a GitHub credential) and the nvidia key, violating least privilege and the entrypoint's "no GH tokens" rule.
- **Mount scoped auth.json into the container** — rejected: more plumbing (entrypoint check change, mount changes in both drivers), equivalent security to the chosen approach.
- **Require OPENROUTER_API_KEY in host env** — rejected: changes the user's workflow, pi stores the key in auth.json for a reason.
- **Env-var injection from pi's auth.json (chosen)** — the driver reads `~/.pi/agent/auth.json`, extracts only the provider keys corresponding to the allowlisted env vars, and writes them into the existing `secrets.env` (chmod 600, `--env-file`, removed on cleanup). Env vars set on the host take priority as explicit overrides.

### Decision

The driver's `write_env_file()` function, after forwarding allowlisted host env vars, also resolves credentials from `~/.pi/agent/auth.json` for any allowlisted LLM provider env var that remains unset. The mapping follows pi's own `envMap` (OPENROUTER_API_KEY ↔ openrouter, ANTHROPIC_API_KEY ↔ anthropic). The resolution is scoped to the allowlist — env vars not in the allowlist are never resolved from auth.json (safety: the github-copilot and nvidia keys never enter the container). No key values are ever echoed to stdout/stderr by the driver.

Additionally, the model resolution falls back to `PI_PROVIDER/PI_MODEL` (pi's own env vars) when neither `IMPLEMENTER_MODEL` nor the config model is set, so the sandboxed agent natively uses "the same model as pi".

### Rationale

- **Minimal change**: the envfile plumbing already exists (chmod 600, `--env-file`, cleanup); only the source of the key value changes.
- **Least privilege**: only allowlisted provider keys are extracted; the `github-copilot` access token never enters the container.
- **Same source as pi**: resolves the key from the same file pi reads, so the user never needs to manage a separate credential for the sandbox.
- **Defense in depth**: `sanitize-session.sh` already redacts `sk-or-v1-*` patterns; the entrypoint's "no GH tokens" guard remains; the envfile is removed on cleanup.
- **Bootstrapping note**: this fix is a prerequisite for the implementer to run any task. The implementer cannot fix its own credential path, so this change was implemented directly in the product-layer session rather than delegated to the implementer pipeline.

### Consequences

- `bin/implementer-run.sh` and `bin/review-run.sh` `write_env_file()` gain a credential resolution step after the allowlist loop.
- `workspace-portability/container/run-sandbox.sh` gets the same auth.json fallback.
- The entrypoint `OPENROUTER_API_KEY`/`ANTHROPIC_API_KEY` check stays unchanged (the env var is now populated).
- On first boot, if no LLM credential is found in either env or auth.json, the driver fails fast before spinning up any container (saves 3 respawn cycles).
- The model fallback (`PI_PROVIDER/PI_MODEL`) makes the sandboxed agents track pi's current model automatically if the config lacks one.

### Revision triggers

- If pi changes its auth.json schema (key names, provider structure, file location), the mapping must be updated.
- If the allowlist expands to include a provider whose auth.json key name doesn't follow the `PROVIDER_API_KEY` → `provider.key` convention, the mapping must be extended.
