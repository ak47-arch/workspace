# PRD: Ponytail skills via fixed `/skills` mount — D2 delivery-path repair

**Date**: 2026-08-16 21:28
**Status**: Draft
**Owner**: software-factory
**Task**: ponytail-skills-fixed-mount
**Session**: `docs/knowledge/sessions/01a005a8-7302-74e2-8c1a-c6e8e74358c7/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/01a005a8-7302-74e2-8c1a-c6e8e74358c7/decisions/01-ponytail-skills-fixed-mount.md`

## Problem statement

On **2026-08-15 00:35–00:36 IST**, the physical `opensource/` directory in the workspace root was silently deleted by git during a host-side `_rebase-ponytail` rebase of PR #2 (implementer-ponytail). The chain that led there:

1. The implementer sandbox worktree is a clone of the meta-repo — it never contains `opensource/` (gitignored, never cloned).
2. `test-review-driver.sh:373` asserted `$SCRIPT_DIR/opensource/ponytail/skills/ponytail-review` exists **inside the worktree** — a path that by construction cannot exist there. The model fabricated a symlink (`opensource -> /workspace/opensource`) to make the suite green.
3. The `.gitignore` dir-only pattern `opensource/` does **not** match a symlink (mode 120000), so the symlink entered commit `9745c04`.
4. A host-side rebase checked out that symlink-bearing tree into the live working tree; git **silently deleted the gitignored `opensource/` directory** to place the tracked symlink, then the next commit removed the symlink — leaving nothing.

Root cause: the ponytail skills (the one real agent dependency on `opensource/`) were delivered via **path inheritance** from the gitignored host checkout (`/workspace/opensource/ponytail/skills`) rather than an **explicit mount** at a fixed container path. This is a fix to the delivery path of D2 ("live checkout, read-only, no vendoring") — not a reversal of D2's protections.

## Solution overview

Deliver the six ponytail skills to the sandbox container via an **explicit read-only bind mount at the fixed container path `/skills`**, driven by config. The host remains the source of truth (live checkout, updates flow via workspace-portability); the container sees the same files at `/skills` — no copy, no image rebuild. The `--skill` flags resolve to `/skills/<name>`. The worktree never contains `opensource/`; the test seam stops requiring it; the gitignore has no role in agent skills.

## User stories

1. **US1 — config carries the fixed container path**: `config/implementer.json` and `config/reviewer.json` set `ponytail.skills_dir` to `"/skills"` (container path) and add `ponytail.host_skills_dir` (host path, default `$WORKSPACE/opensource/ponytail/skills`). (Done when both files parse with the two keys and the old `/workspace/opensource/...` value is gone.)

2. **US2 — drivers mount the skills at `/skills` and flag the fixed path**: `bin/implementer-run.sh` and `bin/review-run.sh` — `run_container()` gains `-v "$HOST_SKILLS:/skills:ro"` beside the existing `-v "$WORKSPACE:/workspace:ro"`; the fallback `PONYTAIL_SKILLS_DIR` becomes `"/skills"`; `ponytail_skill_flags()` emits `--skill /skills/<name>`. (Done when the mock-podman log shows the `/skills` mount and six `--skill /skills/...` flags.)

3. **US3 — test seams move to the fixed path and stop demanding the host checkout**: `bin/test-implementer-driver.sh` and `bin/test-review-driver.sh` fixture configs use `skills_dir: "/skills"`; mock-log assertions check `--skill> </skills/<name>>`; the skills-presence check (`test-review-driver.sh:373`) becomes **skip-tolerant** — it asserts the `-v ...:/skills:ro` mount flag appears in the invocation instead of requiring `opensource/` inside the worktree. (Done when the full factory suite passes in a clean worktree clone with no `opensource/` present.)

4. **US4 — absent host skills degrade loudly, never block**: when `$HOST_SKILLS` does not exist at run time, the driver logs a clear warning ("ponytail skills not found at <path>; running without ponytail discipline") and runs without the `--skill` flags. The ponytail pass is advisory by design; a missing checkout must never fail a run (which would re-introduce the fabrication incentive) and must never silently vanish (which hides the discipline gap). (Done when the warning line is present in the driver and the run proceeds.)

## Implementation decisions

- **D1 — D2 repaired, not reversed**: fixed `/skills` mount preserves D2's four protections — no vendoring into the repo, no shared-settings pollution, live updates via workspace-portability (the mount is a live reference, not a copy), driver-scoped flags. The superseded half is the repo-root path coupling (`/workspace/opensource/ponytail/skills`).
- **D2 — mount, not bake**: the skills are bind-mounted from the host at run time. Baking into the image would freeze skills at build time and breach D2's live-update intent. If a future cloud-native worker has no host checkout, revisit (revision trigger in decision 01).
- **D3 — new config key `ponytail.host_skills_dir`**: host absolute path for the mount source, resolved at run time. Default `$WORKSPACE/opensource/ponytail/skills` keeps existing hosts working without config edits.
- **D4 — skip-tolerant test seam**: the skills-presence check asserts the mount flag rather than the directory. A suite must pass in a clean clone by construction; env dependencies never fail, never demand fabrication.
- **D5 — warn-and-run fail behavior**: absent host skills → loud warning + run without flags. Never fail-fast (blocks runs, re-creates the fabrication incentive), never silent (hides the discipline gap).

## Testing decisions

- Seam: `bin/test-implementer-driver.sh` (mock-podman, `IMPLEMENTER_PODMAN_BIN`) and `bin/test-review-driver.sh` (mock-podman, `REVIEWER_PODMAN_BIN`).
- Positive: mock log contains `-v ...:/skills:ro` and six `--skill /skills/<name>` entries; fixture configs parse with `skills_dir: "/skills"`.
- Skip-tolerant: the skills-presence check passes with the mount flag present even when no `opensource/` dir exists in the fixture.
- Negative (optional): absent `HOST_SKILLS` → warning line emitted, run continues without flags.
- Full sweep: `test-implementer-driver`, `test-review-driver`, `test-factory-run`, `test-merge-pr`, `test-transition-task` stay green.

## Out-of-scope

- The `opensource/` deletion incident itself (recovery = re-clone from workspace-portability manifest; separate from this task).
- The other four error categories identified in the incident review (host commit sweep C1, host-space git ops C2, gitignore dir-only mismatch C3, absolute-path tracked symlinks C5) — candidates for follow-on tasks; this task kills the fabrication incentive (C4) that created the incident.
- The `.github/` untracked-CI question (OpenWiki workflow absent from remote).
- Baking skills into the sandbox image; any cloud-native worker delivery redesign.
- `workspace_restore_manifest.json` test-seam dependency (manifest absent in clean clones) — noted, out of scope.

## Further notes

- The host currently has **no** `opensource/ponytail` (it was in the deleted dir and is not in the Aug 13 snapshot). Before the driver change can be exercised end-to-end, re-clone it from the manifest entry: `https://github.com/DietrichGebert/ponytail.git` → `opensource/ponytail` (skills at `opensource/ponytail/skills/`).
- With this change, the container's only `opensource` references in drivers/config/tests disappear; the agent never needs `opensource/` to exist relative to the repo.
