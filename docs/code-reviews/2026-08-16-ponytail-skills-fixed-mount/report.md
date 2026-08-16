# Code Review

- Reviewed: https://github.com/ak47-arch/workspace/pull/4 (repo: ak47-arch/workspace, PR #4)
- Task: ponytail-skills-fixed-mount · PRD: docs/prd-queue/2026-08-16-ponytail-skills-fixed-mount.md · Review session: 0bb584c8-f18c-4655-97b9-bc100c39a087
- Base: 85a6c4b08e40fab84a25b0a4735abe66620eaac6 → Head: a2c1b8906af5503b2da4034cb0f5bfbab8af1dc7

## Verdict

**APPROVE** — all 4 user stories implemented, scope fully contained to the PRD file map, all deterministic checks pass, and the factory verification sweep is green (one pre-existing, out-of-scope failure). Only advisory over-engineering findings (ponytail-review), none blocking.

## Verification results

PRD acceptance set = the "Full sweep" from **Testing decisions** (`test-implementer-driver`, `test-review-driver`, `test-factory-run`, `test-merge-pr`, `test-transition-task`) plus the positive/skip-tolerant seams. All run in `/sandbox/worktree` (read-only) with mock-podman seams (no podman/jq in container — the drivers' built-in mock seams are the intended path).

| Command | Result | Evidence |
|---|---|---|
| `bin/test-implementer-driver.sh` | **55 passed, 1 failed** | Failed: `resolve_repo MANIFEST_BRANCH = 'master' — expected public-release` (pre-existing, out of scope — depends on gitignored `workspace-portability/workspace_restore_manifest.json` absent in clean clones; PRD "Further notes" declares it out of scope). New ponytail assertions all green. |
| `bin/test-review-driver.sh` | **63 passed, 0 failed** | `All tests passed.` — incl. skip-tolerant mount-flag + US4 warn-and-run assertions. |
| `bin/test-factory-run.sh` | **22 passed, 0 failed** | `All tests passed.` |
| `bin/test-merge-pr.sh` | **8 passed, 0 failed** | `All tests passed.` |
| `bin/test-transition-task.sh` | **45 passed, 0 failed** | `Results: 45 passed, 0 failed` |

Deferred (recorded, never skipped): real end-to-end podman run (no container runtime in sandbox); host `opensource/ponytail` re-clone (required by PRD "Further notes"). Neither is runnable here; both are in the UAT hand-off list.

## Story-by-story

- **[PASS] US1 — config carries the fixed container path**: `config/implementer.json` + `config/reviewer.json` set `ponytail.skills_dir: "/skills"` and add `ponytail.host_skills_dir: "$WORKSPACE/opensource/ponytail/skills"`; old `/workspace/opensource/...` value gone. Verified both files parse via python `json.load` → `{'skills_dir': '/skills', 'host_skills_dir': '$WORKSPACE/opensource/ponytail/skills', 'default_mode': 'ultra'}`.
- **[PASS] US2 — drivers mount skills at `/skills` and flag the fixed path**: `bin/implementer-run.sh` + `bin/review-run.sh` — jq-less fallback `PONYTAIL_SKILLS_DIR="/skills"`; read `host_skills_dir` (resolving `$WORKSPACE`); `run_container()` adds `-v "$HOST_SKILLS:/skills:ro"` beside `-v "$WORKSPACE:/workspace:ro"`; `ponytail_skill_flags()` emits `--skill $PONYTAIL_SKILLS_DIR/$s` = `/skills/<name>`. Verified: mock-podman log shows `/skills:ro` mount AND `flag count = 6` `--skill /skills/...` entries.
- **[PASS] US3 — test seams move to fixed path, stop demanding host checkout**: `bin/test-implementer-driver.sh` + `bin/test-review-driver.sh` fixture configs use `skills_dir: "/skills"`; implementer mock-log assertion `--skill> </skills/$sk>`; the former `test-review-driver.sh:373` dir-presence check is replaced by a skip-tolerant `:/skills:ro` mount-flag assertion. Verified green; suite passes in this clean clone with **no** `opensource/` present.
- **[PASS] US4 — absent host skills degrade loudly, never block**: both drivers emit `WARN: ponytail skills not found at ${HOST_SKILLS:-<unset>}; running without ponytail discipline` (stderr) and run WITHOUT the `--skill` flags / mount when `$HOST_SKILLS` is absent. Verified: US4 branch assertions pass in both test drivers; `[ -d "$HOST_SKILLS" ]` guards the mount/flags.

## Deterministic checks

- **[PASS] D1 — PR metadata sane**: head commit `a2c1b89 implementer(ponytail-skills-fixed-mount): run 0ded66e7…[factory]` — well-formed factory PR; base `85a6c4b`/head `a2c1b89` both resolve; diff is non-empty and scoped to 6 files.
- **[PASS] D2 — Worktree clean / read-only**: `git status` shows detached HEAD at a2c1b89, clean tree; no reviewer mutations (guardrail re-verified clean at finish).
- **[PASS] D3 — Scope containment**: all 6 changed files (`config/implementer.json`, `config/reviewer.json`, `bin/implementer-run.sh`, `bin/review-run.sh`, `bin/test-implementer-driver.sh`, `bin/test-review-driver.sh`) are exactly within the PRD file map. No out-of-scope edits, no stray deps.
- **[PASS] D4 — Scope ⊆ PRD file-map**: every file the PRD file map claims is present in the diff; nothing promised is missing.
- **[PASS] D5 — Story → diff coverage**: US1→configs; US2→drivers (`/skills` mount + flags); US3→test seams (fixture configs + mount-flag assertion); US4→drivers warn-and-run + test assertions. No capability in the diff that no story asks for.
- **[PASS] D6 — No secrets / stray deps**: diff scan for `api_key|secret|password|token|PRIVATE KEY` clean; no `.env`; no `package/gem/requirements/go.mod/lock` files changed.
- **[PASS] D7 — Implementer report matches actual diff**: `docs/implementations/2026-08-16-ponytail-skills-fixed-mount/report.md` claims match — per-story status, the `/skills` mount + six flags, the 55/1, 63/0, 22/0, 8/0, 45/0 sweep numbers all reproduce exactly in my run; the single pre-existing manifest failure is accurately called out and is out of scope.

## Judgment checks

- **[PASS] J1 — Story intent**: observable behavior holds. The container genuinely sees skills at `/skills` via the mount; flags resolve to `/skills/<name>`; absent host checkout → loud warning + flagless run. US1's "done when old value gone" holds (grep confirms no `/workspace/opensource/...` skill path remains in configs/drivers/tests).
- **[PASS] J2 — PRD-decision conformance**: D1 (mount, not vendoring — read-only `:ro`, worktree never contains opensource); D2 (bind mount, live — no bake); D3 (new `host_skills_dir` key, default `$WORKSPACE/opensource/ponytail/skills` preserved); D4 (skip-tolerant mount-flag seam); D5 (warn-and-run). All honored. The conditional mount (mount only when host dir present) is consistent with both US2 and US4 and is documented in decision 01.
- **[PASS] J3 — Edge / error paths**: absent `$HOST_SKILLS` → warn + skip mount/flags (no fail-fast, no silent). `set -euo pipefail` is used and the empty `skills_mount=()` array expands safely under `set -u` on bash 4.4+ (verified on bash 5.2). `$WORKSPACE` braced/unbraced expansion handled. jq-less fallback present. Missing manifest only breaks the out-of-scope resolve_repo check, never the ponytail path.
- **[PASS] J4 — Ponytail over-engineering pass (ultra)**: see Advisory findings. Diff is otherwise lean; the conditional-mount array and warn-and-run are the minimum that satisfies US2/US4.
- **[PASS] J5 — UAT gaps**: enumerated in hand-off list (real podman end-to-end not run; host skills re-clone needed; manifest dependency; `$WORKSPACE` resolution in the real env).

## Findings

### Blocking (→ REQUEST_CHANGES)
- None.

### Advisory (consider / over-engineering)
- `bin/implementer-run.sh:73` / `bin/review-run.sh:63`: `yagni` — the `${WORKSPACE}` braced-form expansion line (`HOST_SKILLS="${HOST_SKILLS//\$\{WORKSPACE\}/$WORKSPACE}"`) handles a form no config/fallback actually emits (both use unbraced `$WORKSPACE`). Replacement: drop that line; the unbraced line 72/62 suffices. `net: -2 lines possible.`

## Ponytail debt (harvested from changed files)

No ponytail: debt. Clean ledger. (`grep -rnE '(#|//) ?ponytail:'` over the 6 changed files → no markers.)

## UAT hand-off list

1. **Host skills re-clone (required)**: re-clone `https://github.com/DietrichGebert/ponytail.git` → `opensource/ponytail` (skills at `opensource/ponytail/skills/`) so the host `$WORKSPACE/opensource/ponytail/skills` mount source exists. Until then the container runs with the loud US4 warning and no ponytail discipline (expected).
2. **Real end-to-end podman run**: confirm a real `podman run` mounts `/skills:ro` and passes six `--skill /skills/...` flags to pi (not exercised in sandbox — no container runtime).
3. **`$WORKSPACE` resolution in the real driver env**: confirm `ponytail.host_skills_dir` expands to the intended host path (sandbox verified it expands to the fixture `$SMOKE` path; real env uses the host workspace root).
4. **`test-implementer-driver.sh` manifest branch failure**: resolves when `workspace-portability/workspace_restore_manifest.json` is present (out-of-scope dependency); verify separately in the host workspace.
5. **Advisory (non-blocking)**: consider dropping the unused `${WORKSPACE}` braced-form expansion in both drivers (2 lines).
