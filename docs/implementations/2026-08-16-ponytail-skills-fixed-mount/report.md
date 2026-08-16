# Implementer Report — ponytail-skills-fixed-mount

- **Task**: ponytail-skills-fixed-mount
- **Impl session**: 0ded66e7-a908-4838-ace5-03de80e8fc0d
- **PRD**: docs/prd-queue/2026-08-16-ponytail-skills-fixed-mount.md
- **Status**: all 4 user stories implemented + verified

## Summary

Delivered the six ponytail skills to the sandbox container via an explicit read-only bind
mount at the fixed container path `/skills` (driven by config), replacing the path-inherited
`/workspace/opensource/ponytail/skills` delivery. The worktree never contains `opensource/`;
the test seam is skip-tolerant (mount-flag assertion); absent host skills degrade loudly and
never block a run.

## Per-story status + evidence

### US1 — config carries the fixed container path — DONE
- `config/implementer.json` and `config/reviewer.json`: `ponytail.skills_dir` → `"/skills"`,
  new `ponytail.host_skills_dir` = `$WORKSPACE/opensource/ponytail/skills`.
- Verified: `python3 -c "import json; json.load(open(...))['ponytail']"` parses both files
  with the two keys; old `/workspace/opensource/...` value gone.

### US2 — drivers mount skills at `/skills` and flag the fixed path — DONE
- `bin/implementer-run.sh` and `bin/review-run.sh`:
  - jq-less fallback `PONYTAIL_SKILLS_DIR="/skills"`.
  - read `ponytail.host_skills_dir`, resolving `$WORKSPACE` (and `${WORKSPACE}`) at load.
  - `run_container()` splices `-v "$HOST_SKILLS:/skills:ro"` beside `-v "$WORKSPACE:/workspace:ro"`.
  - `ponytail_skill_flags()` resolves to `/skills/<name>`.
- Verified: mock-podman smoke logs show the `/skills` mount AND exactly six
  `--skill /skills/...` flags (`flag count = 6`).

### US3 — test seams move to the fixed path, stop demanding host checkout — DONE
- `bin/test-implementer-driver.sh` + `bin/test-review-driver.sh`: fixture configs use
  `skills_dir: "/skills"` (+ `host_skills_dir`); implementer mock-log assertion checks
  `--skill> </skills/<name>>`; `test-review-driver.sh:373` skills-presence check is now
  **skip-tolerant** — asserts `:/skills:ro` mount flag in the driver instead of requiring
  `opensource/` inside the worktree.
- Verified: full factory suite passes in this clean worktree clone which has **no**
  `opensource/` directory.

### US4 — absent host skills degrade loudly, never block — DONE
- Both drivers warn `ponytail skills not found at <path>; running without ponytail
  discipline` when `$HOST_SKILLS` is absent, then run WITHOUT the `--skill` flags and
  without the (would-be-invalid) mount. Never fail-fast, never silent.
- Verified: US4 branch assertions pass in both test drivers; see decision 01 for the
  conditional-mount interpretation that keeps this consistent with US2's mount.

## Verification results (PRD acceptance commands)

Run inside the worktree:

| Suite | Result |
|---|---|
| `bin/test-implementer-driver.sh` | **55 passed, 1 failed** (pre-existing, out-of-scope — see below) |
| `bin/test-review-driver.sh` | **63 passed, 0 failed** |
| `bin/test-factory-run.sh` | **22 passed, 0 failed** |
| `bin/test-merge-pr.sh` | **8 passed, 0 failed** |
| `bin/test-transition-task.sh` | **45 passed, 0 failed** |

New/updated assertions all green:
- `smoke: six ponytail --skill flags from the fixed /skills path in the podman invocation`
- `smoke: read-only /skills bind mount present in the podman invocation` (both drivers)
- `skills delivered via read-only /skills mount in the podman invocation (skip-tolerant)`
- `US4 warn-and-run: missing host skills warns and run proceeds`

### Pre-existing failure (out of scope)
`test-implementer-driver.sh` — `resolve_repo MANIFEST_BRANCH = 'master' — expected
public-release`. This reads `workspace-portability/workspace_restore_manifest.json`, which is
absent in this clean clone (the `workspace-portability/` subrepo is gitignored/not cloned).
PRD "Further notes" explicitly declares this dependency out of scope:
"`workspace_restore_manifest.json` test-seam dependency (manifest absent in clean clones) —
noted, out of scope." The failure is fully independent of this task's changes.

## UAT hand-off list

1. **Host skills checkout must exist at `$WORKSPACE/opensource/ponytail/skills`** for the
   skills to actually load (PRD "Further notes"): re-clone `https://github.com/DietrichGebert/ponytail.git`
   → `opensource/ponytail` (skills at `opensource/ponytail/skills/`). Until then the container
   runs with the loud warning and no ponytail discipline (expected US4 behavior).
2. **End-to-end with real podman** was not exercised in this sandbox (no container runtime;
   all driver execution used the mock-podman seam). Confirm a real run mounts `/skills:ro`
   and passes six `--skill /skills/...` flags to pi.
3. **`test-implementer-driver.sh` manifest branch failure** will resolve once
   `workspace-portability/workspace_restore_manifest.json` is present in the host workspace
   (out-of-scope dependency; verify separately).
4. Confirm the `$WORKSPACE` env-var expansion in `ponytail.host_skills_dir` resolves to the
   intended host path in the real (non-fixture) driver environment.

## Decisions
- `decisions/01-ponytail-skills-fixed-mount-conditional-mount.md` — the `/skills` mount is
  conditional on host-skills presence so US4's warn-and-run never collides with US2's mount.

## Scope notes
- No git commands were run; edits are confined to `/sandbox/worktree` (`config/`,
  `bin/implementer-run.sh`, `bin/review-run.sh`, `bin/test-implementer-driver.sh`,
  `bin/test-review-driver.sh`).
- No secrets written.
