# Known Issues — Post-Migration Cleanup

These issues were identified after completing the `llm_client` shared-package migration
(Phases 1–3). They are functional — all three apps are running and passing requests —
but represent technical debt that should be resolved before the next deployment or
before onboarding another project.

---

## Issue 1: `llm_client` served via runtime mount + PYTHONPATH hack

**Affects:** `feed_analyser/docker-compose.yml`, `survival-infrastructure/docker-compose.yml`  
**Severity:** Medium — works but fragile

### What
Both feed-analyser and survival-infrastructure containers get `llm_client` through a
volume mount (`../llm:/opt/llm:ro`) plus `PYTHONPATH=/opt/llm` in the environment,
rather than having the package baked into the Docker image.

### Why it matters
- If someone clones the repos into a different directory layout, the relative path
  `../llm` won't resolve and `llm_client` imports will fail.
- The images are incomplete — they cannot run standalone without the mount.
- The `PYTHONPATH` approach bypasses normal dependency management.

### Fix
Add the `llm-client` package as a proper dependency in each project's
`requirements.txt` (pointing to the git repo or a local path during build),
and `pip install` it during `docker build` so it lands in the image's
site-packages. Remove the `../llm` volume mount and `PYTHONPATH` env var.

---

## Issue 2: `llm` repo `pi_master` branch not pushed to origin

**Affects:** `llm/` (remote)  
**Severity:** ~~High~~ ✅ Resolved

### What
The `llm_client` source files live on the `pi_master` branch, but that branch
had not been pushed to `origin`. The remote `origin/pi_master` was several commits
behind and did not contain the `llm_client` package.

### Resolution
Pushed on 2026-07-03. `origin/pi_master` is now at `c5db2ac` and all tags
(`v0.1.0` – `v0.5.1`) have been pushed. Confirmed: `git rev-list --count origin/pi_master..pi_master` → `0`.

---

## Issue 3: `start_stack.sh` references missing `compose_env_preflight.sh`

**Affects:** `survival-infrastructure/start_stack.sh`  
**Severity:** High — startup script is broken

### What
Line 3 of `start_stack.sh` calls:
```bash
bash "$LLM_DIR/scripts/compose_env_preflight.sh"
```

But the `llm/scripts/` directory was deleted during the `llm_client` migration
(the scripts were pruned as dead code). The file no longer exists, so every
invocation of `start_stack.sh` fails immediately with exit code 127.

### Why it matters
The primary startup script for the survival-infrastructure stack is broken.
Developers must use `docker-compose up -d` directly (which bypasses the
preflight checks but works).

### Fix
Either:
- Restore the preflight script (create a minimal version that just validates
  `LLAMA_CPP_DIR` and the shared network), or
- Remove the preflight call from `start_stack.sh` and inline the checks it
  performed.

---

## Issue 4: Reasoning parameters locked in llama-server startup flags, not controllable per-workflow

**Affects:** `llm/service_models.yaml`, `llm/openai_compatible_provider.py`, `llm/llm_client/config.py`
**Severity:** Medium — functional constraint, not a bug

### What
Reasoning-related params (`--reasoning`, `--reasoning-budget`, `--reasoning-format`)
are set as startup-only `extra_args` in `llm/service_models.yaml` under the active
provider:

```yaml
providers:
  - id: gemma_e2b_q4_local
    ...
    connection:
      managed_server:
        extra_args:
          - --reasoning
          - "off"
          - --reasoning-budget
          - "0"
          - --reasoning-format
          - "none"
```

These flags are passed to the `llama-server` binary at process launch via
`local_server_runtime.py` → `_build_server_command()` and cannot be changed
per-request through the OpenAI-compatible API.

This conflicts with the `llm_client` design goal: a per-project `config/workflows.yaml`
should be the single source of truth for workflow-level model behaviour. Currently,
even after the migration, some model parameters remain hardcoded in
`service_models.yaml` at the server level.

### Why it matters
- Some workflows need reasoning enabled, others don't. The architecture has no way
  to express this at the workflow level.
- The `WorkflowDef` schema in `llm_client/config.py` has no `reasoning`, `reasoning_budget`,
  `reasoning_format`, or generic `extra_body` passthrough field.
- The `openai_compatible_provider.py` payload builder only sends `model`, `messages`,
  `temperature`, and `max_tokens` — no `extra_body` propagation.
- Adding a new workflow with different reasoning requirements requires either:
  (a) restarting the server with different flags (disruptive), or
  (b) spawning a separate llama-server instance (memory-heavy, ~8GB extra per instance
      for Gemma E2B Q4).

### Root cause analysis
`llama-server`’s `--reasoning` flags control token-tag parsing at the server level
(extracting `<think>...</think>` blocks into `message.reasoning_content`). They are
not recognized as per-request parameters. This is a limitation of the llama-server
binary, not our abstraction.

For Gemma models specifically, `--reasoning off` is functionally a no-op — Gemma
does not emit thinking tags natively. Actual "reasoning" (step-by-step thought) is
controlled entirely by the system prompt, which the client already manages per-workflow.

### Potential fixes

**Short-term (prompt-based, zero resource cost):**
- Remove `--reasoning off` from `service_models.yaml` (it's irrelevant for Gemma).
- Control whether the model "reasons" through per-workflow system prompts in
  `config/workflows.yaml`. This already works today.

**Medium-term (schema + provider improvements):**
- Add a generic `extra_body` dict field to `WorkflowDef` in `llm_client/config.py`.
- Thread `extra_body` through `WorkflowClient.complete()` → payload dict in
  `openai_compatible_provider.py`.
- This future-proofs against servers that *do* support per-request reasoning
  (Anthropic, OpenAI o-series, future llama-server releases).

**Long-term (multi-instance, expensive):**
- Add a second provider entry in `service_models.yaml` pointing to a different port
  (e.g., `gemma_no_reasoning` on port 18012, `gemma_with_reasoning` on port 18013).
- Each gets its own `llama-server` process with different startup flags.
- Each project's `config/workflows.yaml` selects the right `model_ref` per workflow.
- Cost: ~double the VRAM/RAM per additional server instance.