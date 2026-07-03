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
**Severity:** High — source of truth is local-only

### What
The `llm_client` source files live on the `pi_master` branch, but that branch
has not been pushed to `origin`. The remote `origin/pi_master` is several commits
behind and does not contain the `llm_client` package at all.

Commits missing on remote:
- `c3163f4` — feat: add llm_client package — shared workflow-driven LLM client
- `16704a1` — fix: pass user_prompt (not messages array) to fallback functions
- `c5db2ac` — docs: add llm_client section to README, finalize CHANGELOG

### Why it matters
Anyone pulling from `origin` gets a repo without the `llm_client/` directory.
CI/CD builds will fail, and other developers cannot work on the package.

### Fix
```
cd llm
git push origin pi_master --tags
```

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