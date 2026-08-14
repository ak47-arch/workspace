# Implementer Run Report — implementer-ponytail

- **Session UUID**: 8483b243-ad9a-4e00-be82-0cdf26a8801d
- **PRD**: `docs/prd-queue/2026-08-14-implementer-ponytail.md`
- **Date**: 2026-08-14

## Per-story status

### US1 — config — DONE
- **What changed**: `config/implementer.json` gains a `ponytail` block
  (`"skills_dir": "/workspace/opensource/ponytail/skills"`,
  `"default_mode": "ultra"`) and `PONYTAIL_DEFAULT_MODE` was added to
  `env_allowlist`.
- **Evidence**: `python3 -c json.load(...)` parses the file; the allowlist
  enumerates `PONYTAIL_DEFAULT_MODE` as the 7th entry and `ponytail` carries the
  two required keys.

### US2 — driver config reads + env file — DONE
- **What changed**: `bin/implementer-run.sh` reads `ponytail.skills_dir` and
  `ponytail.default_mode` via the existing `cfg()` seam (jq branch, lines
  57–58) with non-jq fallbacks (`/workspace/opensource/ponytail/skills`,
  `ultra`, lines 72–73 — mirroring `review-run.sh`); the fallback `env_allowed()`
  gains `PONYTAIL_DEFAULT_MODE` (line 89); `write_env_file()` emits
  `PONYTAIL_DEFAULT_MODE=<default_mode>` when set (lines 345–347). Env file
  still contains ONLY allowlisted LLM/Langfuse keys + the mode variable —
  never GH tokens (invariant preserved, asserted in tests).
- **Evidence**: `bin/test-implementer-driver.sh` "env file forces
  PONYTAIL_DEFAULT_MODE=ultra" and "env file excludes GITHUB_TOKEN" pass.

### US3 — six `--skill` flags in the pi invocation — DONE
- **What changed**: `bin/implementer-run.sh` defines
  `PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit ponytail-debt
  ponytail-gain ponytail-help)` and a `ponytail_skill_flags()` seam emitting
  `--skill <skills_dir>/<name>` per name (lines 356–362); `run_container()`
  collects them into `pony` and injects `${pony[@]}` into the pi command
  between the session args and the persona append (line 421), matching the
  `review-run.sh` injection position.
- **Evidence**: end-to-end smoke (mock podman, `--dry-run`) asserts all six
  flags resolve under `/workspace/opensource/ponytail/skills/` in the container
  invocation (6 flags, `flag count = 6`).

### US4 — persona prose → loaded-skills pointer — DONE
- **What changed**: `.pi/agents/implementer.md` "Working style: ponytail
  (always-on directive)" section rewritten to "Working style: ponytail (loaded
  as real skills)" — states the discipline is loaded as real `--skill` skills
  (ponytail = always-on style; `ponytail-review`/`ponytail-audit`/
  `ponytail-debt`/`ponytail-gain`/`ponytail-help` used as appropriate). All five
  factory binding rules retained verbatim.
- **Evidence**: persona references loaded skills (7 `ponytail` mentions) and
  retains all 5 binding-rule strings (`Never run any git command`, `only
  allowed to modify`, `Never write secrets`, `Leave the live knowledge index
  alone`, `Run **all** your commands`).

### US5 — tests — DONE
- **What changed**: `bin/test-implementer-driver.sh` gains (a) an env-file
  assertion (`PONYTAIL_DEFAULT_MODE=ultra` present, token-free invariant
  intact, Test 4), and (b) a mocked-podman smoke via the new
  `IMPLEMENTER_PODMAN_BIN` seam executing the driver `main` under `--dry-run`
  and asserting the pi command carries all six `--skill` flags from the live
  skills dir plus the ultra mode (Test 5b). Fixture ships
  `bin/sort-knowledge-index.py` + writable `docs/knowledge/` for the
  `append_decisions_to_index` success path.
- **Evidence**: suite passes 34/34. Negative check (optional) verified
  separately: dropping one skill from the seam drops the flag count to 5 and
  the smoke assertion fails (proving the smoke is not vacuous).

## Verification results

Ran inside `/sandbox/worktree`:

- **AC1**: `bash -n bin/implementer-run.sh` OK; `config/implementer.json` JSON-parses.
- **AC2**: `bin/test-implementer-driver.sh` → **34 passed, 0 failed**.
- **AC3 (full sweep)**:
  - `test-implementer-driver`: **34 passed** (GREEN)
  - `test-review-driver`: **61 passed** (GREEN)
  - `test-factory-run`: **22 passed** (GREEN)
  - `test-merge-pr`: **8 passed** (GREEN)
  - `test-transition-task`: **45 passed** (GREEN)
- **AC4**: grep proves `${pony[@]}` (six `--skill` flags) injected between the
  session args and the persona append in `run_container()`; env file emits
  `PONYTAIL_DEFAULT_MODE=%s` from `write_env_file()`; smoke shows all six flags
  under `/workspace/opensource/` plus `PONYTAIL_DEFAULT_MODE=ultra` in the env file.
- **AC5**: persona section references loaded skills + retains all binding rules.

**jq note**: `jq` is not installed in this sandbox, so the driver exercised the
non-jq fallback path (`PONYTAIL_SKILLS_DIR=/workspace/opensource/ponytail/skills`,
`PONYTAIL_DEFAULT_MODE=ultra`). Both the config and the fallback resolve to the
same values, so acceptance is unaffected.

## UAT hand-off list

1. **Review the persona rewrite** (`.pi/agents/implementer.md`) — confirm the
   loaded-skills wording + retained binding rules read well.
2. **Confirm no regressions** in `bin/review-run.sh` / `config/reviewer.json`
   (out of scope — untouched).
3. **On the host** (which has `jq` and the real container runtime + GH creds):
   confirm a real `--dry-run` then a real run invoke the six `--skill` flags and
   the ultra mode as expected (the sandbox proved this via mock podman, but the
   live container invocation with the actual `sandbox:latest` image should be
   eyeballed once).
4. **Environment bootstrap**: the worktree run required two gitignored
   host-only artifacts to make the full suite green (see decision 01). The host
   already has these; no action needed beyond awareness.

## Decisions emerged

- `outbox/decisions/01-implementer-ponytail-test-env.md` — documenting the
  gitignored-environment bootstrap needed to run the factory suite in a bare
  worktree clone.
