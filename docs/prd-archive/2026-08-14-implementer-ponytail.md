# PRD: Implementer ponytail wiring — real skills via `--skill` flags, replacing the prose directive

**Date**: 2026-08-14
**Status**: Final
**Owner**: software-factory
**Task**: implementer-ponytail
**Session**: `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/04-ponytail-review-worker-skills.md`
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/07-merge-tool-operator-authority-split.md`

## Problem statement

The implementer persona (`.pi/agents/implementer.md`) declares ponytail as a
**prose directive** — a hand-written "Working style: ponytail (always-on
directive)" section that *describes* lazy-senior-dev discipline but never loads
the real skill package at `opensource/ponytail/skills/`. The code-review agent
already uses the real mechanism: the six ponytail skills injected as repeatable
pi `--skill` flags at `PONYTAIL_DEFAULT_MODE=ultra` (decision 04). The implementer
— the factory's other autonomous worker — still operates on the prose claim,
with none of the actual skill tooling.

This task upgrades the implementer to the same real wiring, closing the
implementer↔reviewer asymmetry.

## Solution overview

Mirror the code-review agent's proven ponytail wiring (decision 04) into the
implementer driver (`bin/implementer-run.sh`) and its config
(`config/implementer.json`): load the six skills from the live `opensource/`
checkout via `--skill` flags, carry `PONYTAIL_DEFAULT_MODE=ultra` into the
container env file, and replace the persona's prose directive with a pointer to
the loaded skills — while preserving the factory-specific binding rules that a
skill package cannot know (no git, verify what you build, outbox/brief rules).

No vendoring. No interactive pi-extension/MCP. Read-only `opensource/` mount,
exactly like the reviewer.

## User stories

- **US1 — config**: `config/implementer.json` gains a `ponytail` block
  (`"skills_dir": "/workspace/opensource/ponytail/skills"`,
  `"default_mode": "ultra"`) and `PONYTAIL_DEFAULT_MODE` is added to
  `env_allowlist`. (Done when both are present in the file and the jq-based
  `cfg('.env_allowlist[]')` enumerates the new entry.)
- **US2 — driver config reads + env file**: `bin/implementer-run.sh` reads
  `ponytail.skills_dir` and `ponytail.default_mode` via the existing `cfg()`
  seam with non-jq fallbacks (`/workspace/opensource/ponytail/skills`, `ultra` —
  mirroring `review-run.sh`), the fallback `env_allowed()` also gains
  `PONYTAIL_DEFAULT_MODE`, and `write_env_file()` emits
  `PONYTAIL_DEFAULT_MODE=<default_mode>` when set. The env file still contains
  ONLY allowlisted LLM/Langfuse keys + the mode variable — never GH tokens
  (existing invariant preserved). (Done when the env file written by
  `write_env_file()` contains the `PONYTAIL_DEFAULT_MODE` line and no token.)
- **US3 — six `--skill` flags in the pi invocation**: `implementer-run.sh`
  defines `PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit
  ponytail-debt ponytail-gain ponytail-help)` and a `ponytail_skill_flags()`
  seam emitting `--skill <skills_dir>/<name>` per name (same six + same live
  dir as `review-run.sh`), and injects them into the pi command between the
  session args and the brief append (same position as `review-run.sh`
  ~506-510). (Done when the container's pi invocation contains all six
  `--skill` flags resolving under `/workspace/opensource/`.)
- **US4 — persona prose → loaded-skills pointer**: `.pi/agents/implementer.md`
  — the "Working style: ponytail (always-on directive)" section is rewritten to
  state the discipline is loaded as real skills via `--skill` (ponytail =
  always-on working style; `ponytail-review`/`ponytail-audit`/
  `ponytail-debt`/`ponytail-gain`/`ponytail-help` used as appropriate), while
  KEEPING the factory-specific binding rules (no git — the host owns it; verify
  what you build; respect the brief/outbox; say no to vanishing scope). (Done
  when the section references the loaded skills and every factory binding rule
  still appears.)
- **US5 — tests**: `bin/test-implementer-driver.sh` gains (a) an env-file
  assertion — `PONYTAIL_DEFAULT_MODE=ultra` present, token-free invariant
  intact; (b) a mocked-podman smoke (via a new `IMPLEMENTER_PODMAN_BIN` seam)
  executing the driver `main` under `--dry-run` and asserting the pi command
  carries all six `--skill` flags from the live skills dir plus the ultra mode.
  (Done when the suite passes with the new assertions and all other suites
  remain green.)

## Implementation decisions

- **D1 — mirror `review-run.sh` exactly (decision 04 precedent)**: same
  `PONYTAIL_SKILL_NAMES` array, same `ponytail_skill_flags()` shape, same
  config keys and fallbacks, same env-file line, same injection position
  (session args → `--skill` flags → persona append). The reviewer proved this
  path works and is testable; do not invent a second mechanism.
- **D2 — live checkout, read-only, no vendoring**: flags resolve under the
  mounted `/workspace/opensource/ponytail/skills`; never copy the skills into
  the repo and never touch the shared `.pi/settings.json`.
- **D3 — add `IMPLEMENTER_PODMAN_BIN` seam to `implementer-run.sh`**: mirrors
  `REVIEWER_PODMAN_BIN` so the container invocation is testable end-to-end
  without a container runtime. `run_container()` currently uses bare `podman`
  (incl. `exec podman run` inside its subshell) and `stop_container()` too; all
  call sites go through a `podman_call()` wrapper function (same name as
  `review-run.sh` ~122). Note: `exec` must be dropped for the subshell-invoked
  seam (a function cannot be `exec`'d — same fix already made in
  `review-run.sh`).
- **D4 — default mode `ultra`**, same as the reviewer; do not change the
  implementer directive string semantics beyond what the loaded skills imply.
- **D5 — keep the persona's binding rules**: the skills layer replaces only the
  *discipline prose*; the factory rules (no git, verify, brief/outbox, vanishing
  scope) stay in the persona because the skill package has no knowledge of the
  factory's host-owns-git contract.

## Testing decisions

- Extend `bin/test-implementer-driver.sh` (existing fixture + mock-gh pattern;
  add `make_mock_podman` style mock driven by `IMPLEMENTER_PODMAN_BIN`).
- Fixture note (implementer-specific, unlike the review suite): the implementer
  success path calls `append_decisions_to_index`, which shells out to
  `python3 "$WORKSPACE/bin/sort-knowledge-index.py"` — the smoke fixture must
  ship that script + a writable `docs/knowledge/` so the driver's main path
  completes.
- Positive assertions for env-file and the six flags; the full factory suite
  sweep must stay green (`test-implementer-driver`, `test-review-driver`,
  `test-factory-run`, `test-merge-pr`, `test-transition-task`).
- A negative check is optional: removing one `--skill` flag from the seam must
  fail the smoke assertion (proves the smoke is not vacuous).

## Out of scope

- `bin/review-run.sh`, `config/reviewer.json` — untouched (already wired, decision 04).
- The `prd-reviewer` agent and any other agent — not wired by this task.
- Ponytail skill content, modes, or the `opensource/` checkout itself.
- Interactive pi-extension / MCP wiring; shared `.pi/settings.json`.
- No change to merge/authority behavior (decision 07 stands: implementer raises,
  reviewer reviews, operator merges).

## File map

- `config/implementer.json` — add `ponytail` block + `PONYTAIL_DEFAULT_MODE` to `env_allowlist`.
- `bin/implementer-run.sh` — config reads + fallbacks; `PONYTAIL_DEFAULT_MODE`
  in fallback `env_allowed()`; `write_env_file()` line; `PONYTAIL_SKILL_NAMES`
  + `ponytail_skill_flags()`; `IMPLEMENTER_PODMAN_BIN` seam; `--skill` flags in
  the pi invocation.
- `.pi/agents/implementer.md` — rewrite the ponytail section (US4).
- `bin/test-implementer-driver.sh` — new env-file + smoke assertions (US5).
- Bookkeeping (via `bin/transition-task.sh`, not hand-edited):
  `docs/tasks/implementer-ponytail.md`, `docs/tasks.txt`.

## Acceptance — how "done" is proven

1. `bash -n bin/implementer-run.sh` and `bash -n config/implementer.json` (JSON parses).
2. `bash bin/test-implementer-driver.sh` → all pass including the new
   env-file and six-flag smoke assertions.
3. Full suite sweep green: implementer, review (61), factory-run (22),
   merge-pr (8), transition (45).
4. `grep` proves the pi invocation in `run_container()` carries all six
   `--skill` flags and the env file carries `PONYTAIL_DEFAULT_MODE=ultra`.
5. Persona section (US4) verified: references loaded skills + retains all
   binding rules.

## Context pointers

- Decision 04 (mechanism precedent): `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/04-ponytail-review-worker-skills.md`
- Decision 07 (authority split): `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/07-merge-tool-operator-authority-split.md`
- Working reference: `bin/review-run.sh` lines ~59-75 (config/fallbacks),
  ~442-443 (env-file line), ~448-456 (skill names + flags seam), ~506-510 (injection).
- Task file: `docs/tasks/implementer-ponytail.md`; factory context: `docs/factory-context.md`.
