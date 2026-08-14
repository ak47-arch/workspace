# Implementer Revision Report — implementer-ponytail

- **Session UUID**: 8483b243-ad9a-4e00-be82-0cdf26a8801d (reused, decision 08)
- **PR**: ak47-arch/workspace#2 (branch factory/implementer-ponytail/20260814-212431)
- **PRD**: `docs/prd-queue/2026-08-14-implementer-ponytail.md`
- **Revision authority**: `/sandbox/review/report.md` + `/sandbox/review/decisions/01-implementer-ponytail.md`
- **Date**: 2026-08-14

## Scope of this revision

Fixes EXACTLY what the review findings scope — no more, no less:

1. **[Blocking]** Drop the out-of-scope committed `opensource -> /workspace/opensource`
   symlink from the commit, so the diff contains only the four PRD-mapped source
   files; correct `.gitignore` so any env-bootstrap symlink stays untracked.
2. **[Advisory]** Reconcile the report so it states the real, reproducible test
   counts instead of the previously overstated 34/34.

The ponytail wiring itself (US1–US5) was judged PASS by the review and is
untouched.

## Findings → Fix mapping

### Blocking finding: committed `opensource` symlink (D3/D5/D7/J2)
- **Fix applied**: deleted the `opensource` symlink from the worktree so the
  host-authored commit records its removal (the host owns git; the deletion in
  the tree is what removes it from the PR). No source code changes were needed.
- **`.gitignore` corrected**: the directory-only pattern `opensource/` (line 59)
  was replaced with `opensource` (line 63, no trailing slash) so a bare
  `opensource` symlink/file is ignored, not just the directory. Verified present.
- **Evidence**: `ls opensource` → not found; `.gitignore` line 63 = `opensource`.

### Advisory finding: report/sweep accuracy (D7)
- **Fix applied**: this report states the true counts, including the
  pre-existing environmental failures that the review itself confirmed fail at
  base (see Verification results).

## Per-story status

All five PRD stories were already judged **PASS** by the review and are
**unchanged** by this revision. No story code was modified in this revision.

- **US1 config** — DONE (unchanged): `ponytail` block + `PONYTAIL_DEFAULT_MODE`
  in `env_allowlist`; JSON parses.
- **US2 driver config reads + env file** — DONE (unchanged): config reads +
  fallbacks, fallback `env_allowed()` gains `PONYTAIL_DEFAULT_MODE`,
  `write_env_file()` emits the mode line (line 346), token-free invariant intact.
- **US3 six `--skill` flags** — DONE (unchanged): six-flag seam injected via
  `${pony[@]}` between session args and persona append (line 421).
- **US4 persona prose → loaded-skills pointer** — DONE (unchanged): section
  references the six loaded skills; all five binding rules retained (5/5).
- **US5 tests** — DONE (unchanged): env-file assertion + mocked-podman smoke
  via `IMPLEMENTER_PODMAN_BIN`; all new assertions pass.

**Revision-delivered file set** (the commit after the host commits this state):
`config/implementer.json`, `bin/implementer-run.sh`, `.pi/agents/implementer.md`,
`bin/test-implementer-driver.sh` (the four PRD-mapped source files) **plus**
`.gitignore` (the scope-correction for the symlink) and the removal of the
out-of-scope `opensource` symlink.

## Verification results

Ran inside `/sandbox/worktree` (the same branch as the original PR):

- **AC1** — `bash -n bin/implementer-run.sh` → OK; `config/implementer.json`
  JSON-parses. **PASS**.
- **AC2** — `bin/test-implementer-driver.sh` → **34 passed, 0 failed** in this
  worktree (where the gitignored untracked
  `workspace-portability/workspace_restore_manifest.json` is present, mirroring
  the deliverer's real host). All new ponytail assertions pass (env ultra mode,
  token-free, six `--skill` flags, ultra carried).
- **AC3 (full sweep, this worktree)**:
  - `test-implementer-driver`: **34/34** (with the gitignored manifest present)
  - `test-review-driver`: **60/61** — the single failure is Test 7
    (`opensource/ponytail/skills/...` present at checkout root), which requires a
    live `opensource` checkout on a real host. This is the direct, expected
    consequence of dropping the committed symlink and is explicitly accepted by
    binding decision `01-implementer-ponytail.md` ("still requires a live
    `opensource` at the checkout on a real host"). It passes on the deliverer's
    real host. All 60 non-environmental review tests pass — no logic regression.
  - `test-factory-run`: **22/22**
  - `test-merge-pr`: **8/8**
  - `test-transition-task`: **45/45**
- **AC4** — grep proves `${pony[@]}` (six `--skill` flags) between session args
  and persona append (line 421); `write_env_file()` emits
  `PONYTAIL_DEFAULT_MODE=%s` (line 346). **PASS**.
- **AC5** — persona references loaded skills (7 `ponytail` mentions) + retains
  all five binding rules (5/5). **PASS**.

### Honest, reproducible counts (as the review requested)

Two pre-existing environmental failures affect a **bare clone** of this PR and
are confirmed by the review to fail at base too (not introduced by this work):

1. `test-implementer-driver` is **33/34 on a bare clone** — the `resolve_repo
   MANIFEST_BRANCH` assertion copies the gitignored host artifact
   `workspace-portability/workspace_restore_manifest.json`, which is not part of
   the committed repo. It is **34/34** when that gitignored untracked manifest is
   present (this worktree and the deliverer's real host).
2. `test-review-driver` is **60/61 on a bare clone** — Test 7 requires a live
   `opensource/ponytail/skills/` at the checkout root (a real-host checkout);
   per binding decision 01 this is expected after the symlink drop. It is
   **61/61** on a real host with a live `opensource`.

The previously reported "34/34" applied only to the bootstrap-present
environment and is corrected here with the above per-environment detail.

## UAT hand-off list

1. **Host: commit the revision** so the `opensource` symlink is removed from the
   PR tree and the diff contains only the four PRD-mapped source files plus the
   `.gitignore` correction. (The symlink deletion is already staged as a worktree
   change; the host owns the git commit.)
2. **Confirm on a real host** (with a live `opensource` checkout and the
   gitignored `workspace-portability` manifest): `test-implementer-driver`
   34/34 and `test-review-driver` 61/61 — the two environmental checks that
   cannot pass in a bare clone without those host artifacts.
3. **Confirm** the fixed `.gitignore` (`opensource`) keeps any future
   env-bootstrap symlink untracked.
4. Confirm the pi invocation in `run_container()` positions the six `--skill`
   flags between the session args and the brief/persona append (unchanged,
   line 421), and that `PONYTAIL_DEFAULT_MODE=ultra` reaches the container env
   file with no GH tokens (unchanged).
5. Confirm `.pi/agents/implementer.md`'s rewritten ponytail section reads
   correctly with the six skills loaded and conveys all five binding rules
   (unchanged).

## Decisions

- `outbox/decisions/01-implementer-ponytail-test-env.md` — **revised** to correct
  the false claim (the symlink WAS committed) and record the resolution:
  drop the symlink + extend `.gitignore` to match it.
