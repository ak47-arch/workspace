# PRD: Sandboxed agents resolve LLM credentials from pi's auth.json

**Date**: 2026-08-17 01:55
**Status**: Final
**Owner**: software-factory workspace
**Task**: sandbox-credential-mounting
**Session**: `docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/decisions/04-llm-credential-resolution-from-auth-json.md`

## Problem statement

The factory's sandboxed agents (implementer, reviewer) run inside a container that requires `OPENROUTER_API_KEY` or `ANTHROPIC_API_KEY` in the environment. The host drivers (`bin/implementer-run.sh`, `bin/review-run.sh`) forward only allowlisted host env vars to the container's `secrets.env`. But pi on the host stores its OpenRouter key in `~/.pi/agent/auth.json`, **not** in the host environment — so every container boot failed with `[entrypoint] ERROR: no LLM credential` and the drivers gave up after 3 respawns. The assembly line could not run a single task.

## Solution overview

Add an LLM-credential fallback to `write_env_file()` in both drivers (and the manual `run-sandbox.sh`): for allowlisted provider env vars left unset on the host (`OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`), resolve the key from `~/.pi/agent/auth.json` — the same file pi itself reads — and write it into the existing filtered env file. Host env vars, when set, remain explicit overrides. Keys are scoped strictly to the allowlist mapping, so the `github-copilot` access token and the nvidia key never enter the container. Also make the model resolution fall back to pi's live `PI_PROVIDER/PI_MODEL` when no explicit model or config model is set, so the sandboxed agents natively use the same model as pi.

## User stories

1. When I run the implementer/reviewer with no `OPENROUTER_API_KEY` in my shell env, the driver resolves the key from `~/.pi/agent/auth.json` and the container boots.
2. When I set `OPENROUTER_API_KEY` explicitly on the host, that value wins over auth.json.
3. The github-copilot access token and nvidia key never appear in the container env file.
4. When auth.json is absent and no env var is set, the driver produces an env file without LLM creds (no crash) and the entrypoint fails with its existing clear message.
5. When neither an explicit model nor the config model is set, the sandboxed agent uses pi's current model (`${PI_PROVIDER}/${PI_MODEL}`).

## Implementation decisions

1. **Credential source**: `~/.pi/agent/auth.json` (pi's own credential store), resolved per allowlisted provider env var (decision 04). Mapping: `OPENROUTER_API_KEY` ↔ `openrouter.key`, `ANTHROPIC_API_KEY` ↔ `anthropic.key`.
2. **Mechanism**: env-var injection via the existing `secrets.env` (chmod 600, `--env-file`, removed on cleanup). Entrypoint check unchanged.
3. **Safety**: resolution is scoped to the allowlist — env vars not in `env_allowlist` are never resolved from auth.json. No key values echoed to stdout/stderr. Defense-in-depth: `sanitize-session.sh` redacts `sk-or-v1-*`; entrypoint refuses GH tokens.
4. **Model fallback**: `IMPLEMENTER_MODEL` (or `REVIEWER_MODEL`) → config `model` → `PI_PROVIDER/PI_MODEL`.
5. **Bootstrapping exception**: this fix is a prerequisite for the implementer to run any task, so it was implemented directly in the product-layer session (the implementer cannot fix its own credential path). Normal Small-task flow (product layer → PRD → implementer) resumes with the next task.

## Testing decisions

Seam: the driver functions `write_env_file` and the model-resolution branch, tested via the existing fixture suites.

1. **`bin/test-implementer-driver.sh`** — new "write_env_file: auth.json credential fallback" test with a fake `~/.pi/agent/auth.json`: (a) both provider keys resolved when env vars unset, (b) GH/nvidia keys excluded, (c) host env var overrides auth.json, (d) absent auth.json → no LLM creds, no crash. **Result: 60 passed, 0 failed.**
2. **`bin/test-review-driver.sh`** — same 5 checks for the review driver. **Result: 63 passed, 0 failed.**
3. Existing smoke tests (env file carries no GitHub token, ultra mode carried, six ponytail flags) still pass — no regressions.

## Out-of-scope items

- No changes to the sandbox entrypoint (`OPENROUTER_API_KEY`/`ANTHROPIC_API_KEY` check stays).
- No scoped auth.json mount into the container (option B was considered and rejected — decision 04).
- No changes to GitHub credential handling — the container still never holds repo credentials (brain/hands split).
- No cloud-worker credential story (deferred — local runs only for now).

## Further notes

- The `run-sandbox.sh` manual runner lives in the nested `workspace-portability/` repo (gitignored by the workspace root); its change was committed separately there.
- Verified end-to-end with the real auth.json: `OPENROUTER_API_KEY` is now present in the container env file, so the next implementer run will boot.
- Known edge: a future pi auth.json schema change (key names/locations) must update the mapping in both drivers.
