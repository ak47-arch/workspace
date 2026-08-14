# Code Review

- Reviewed: https://github.com/ak47-arch/workspace/pull/2 (repo: ak47-arch/workspace, PR #2)
- Task: implementer-ponytail · PRD: docs/prd-queue/2026-08-14-implementer-ponytail.md · Review session: 5b63c492-0880-4411-8ff5-26575091edff
- Base: 86363fd55b2adb5098f7826fe62cd6f019e16f89 → Head: 212370c67833ace883e263a17941a1f2f80e84d7

## Verdict

REQUEST_CHANGES — the implementer wired the six ponytail `--skill` flags correctly, but the commit contains an **out-of-scope `opensource -> /workspace/opensource` symlink** that is absent from the PRD file map, contradicts the implementer's own decision record (which states it "never enters the commit"), and is a dangling absolute-host-path artifact on any other clone. The full-suite-sweep acceptance is also not reproducibly green (implementer-driver 33/34 in this worktree) and the report overstates the result (34/34).

## Verification results

RAN (in `/sandbox/worktree`, read-only):

- **AC1** — `bash -n bin/implementer-run.sh` → OK (exit 0). `python3 -c json.load(config/implementer.json)` → OK. **PASS**.
- **AC2** — `bash bin/test-implementer-driver.sh` → **33 passed, 1 failed**.
  - New ponytail assertions all pass: `env file forces PONYTAIL_DEFAULT_MODE=ultra`, `env file excludes GITHUB_TOKEN`, `smoke: six ponytail --skill flags from the live skills dir`, `smoke: PONYTAIL_DEFAULT_MODE=ultra carried`, `smoke: env file carries no GitHub token`, `main executes end-to-end under --dry-run (exit 0)` (flag count = 6).
  - 1 failure: `resolve_repo MANIFEST_BRANCH = 'master' — expected public-release`. Root cause: `cp: cannot stat 'workspace-portability/workspace_restore_manifest.json'` — a **gitignored** host artifact absent from this bare worktree clone (pre-existing environmental, unrelated to the ponytail changes). Implementer's report claims 34/34; not reproducible here without the gitignored manifest.
- **AC3 (full sweep)** — `test-review-driver` **61/61**, `test-factory-run` **22/22**, `test-merge-pr` **8/8**, `test-transition-task` **45/45** all GREEN; `test-implementer-driver` **33/34**. Sweep is **not** fully green (1 environmental failure). **PARTIAL**.
- **AC4** — grep proves `${pony[@]}` (six `--skill` flags) injected between `${sess_args[@]}` and the brief/persona append in `run_container()` (bin/implementer-run.sh ~421, matching review-run.sh position); `write_env_file()` emits `PONYTAIL_DEFAULT_MODE=<default_mode>`. **PASS**.
- **AC5** — `.pi/agents/implementer.md` "Working style: ponytail (loaded as real skills)" references all six loaded skills; all five factory binding rules retained verbatim (lines 50, 55, 58, 61, 64). **PASS**.

## Story-by-story

- [PASS] US1 config — `config/implementer.json` gains `"ponytail": { "skills_dir": "/workspace/opensource/ponytail/skills", "default_mode": "ultra" }` and `PONYTAIL_DEFAULT_MODE` in `env_allowlist`; JSON parses.
- [PASS] US2 driver config reads + env file — `bin/implementer-run.sh` reads `ponytail.skills_dir`/`ponytail.default_mode` via `cfg()` with non-jq fallbacks (lines 57-58 / 72-73); fallback `env_allowed()` gains `PONYTAIL_DEFAULT_MODE` (line 89); `write_env_file()` emits the mode line (lines 345-347); env file remains token-free (asserted).
- [PASS] US3 six `--skill` flags — `PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help)` (line 355) + `ponytail_skill_flags()` seam; `${pony[@]}` injected in the pi invocation between session args and persona append; smoke asserts 6 flags resolving under `/workspace/opensource/ponytail/skills/`.
- [PASS] US4 persona prose → loaded-skills pointer — section rewritten to reference the real `--skill` skills; every factory binding rule still present.
- [PASS] US5 tests — new env-file assertion + mocked-podman smoke (via `IMPLEMENTER_PODMAN_BIN` seam) executing driver `main` under `--dry-run`; all new assertions pass.

## Deterministic checks

- [PASS] D1 PR metadata sane — PR #2, branch `factory/implementer-ponytail/20260814-212431`, base `86363fd` head `212370c`; head commit `[factory]`-stamped; diff non-empty and mostly scoped.
- [PASS] D2 Worktree clean / read-only — `git status` clean on PR head (detached at `212370c`); reviewer made no changes.
- [FAIL] D3 Scope containment — the diff adds `opensource` (`new file mode 120000`, symlink → `/workspace/opensource`), which is **not** in the PRD file map (out-of-scope edit). `git ls-files` shows it is tracked; `git check-ignore opensource` confirms `.gitignore` (`opensource/` on line 59, directory-only) does **not** match the symlink.
- [PASS] D4 Scope ⊆ PRD file-map — all four promised files (`config/implementer.json`, `bin/implementer-run.sh`, `.pi/agents/implementer.md`, `bin/test-implementer-driver.sh`) are present in the diff; bookkeeping files updated via transition.
- [FAIL] D5 Story → diff coverage — all five stories map to hunks; but the committed `opensource` symlink is an artifact no story requests (reverse-direction violation).
- [PASS] D6 No secrets / stray deps — no credentials, no new dependencies; env file remains token-free (asserted). The stray `opensource` symlink is the only extraneous artifact (tracked under D3).
- [FAIL] D7 Implementer report matches actual diff — the archived report + decision `01-implementer-ponytail-test-env.md` state the commit "contains only the four real source files" and that the `opensource` symlink "never enter[s] the commit", but the symlink **is** committed. Report also claims the suite is 34/34 green; actual run is 33/34.

## Judgment checks

- [PASS] J1 Story intent — wiring genuinely loads the six real skills at `ultra`; observable behavior (pi invocation carries all six flags; env carries the mode) confirmed by the smoke test.
- [FAIL] J2 PRD-decision conformance — D1/D3/D4/D5 decisions honored (exact review-run.sh mirror, `IMPLEMENTER_PODMAN_BIN` seam, no `exec`, ultra default, persona rules kept). **Divergence**: committing the `opensource` symlink violates the PRD file map and the "no vendoring / live checkout, read-only" intent of D2, and contradicts the implementer's own decision record.
- [PASS] J3 Edge / error paths — `-n "$PONYTAIL_DEFAULT_MODE"` guard in `write_env_file`; `podman_call` resolves the seam at call time with `podman` fallback; `exec` correctly dropped for the subshell-invoked function seam.
- [PASS] J4 Ponytail over-engineering pass (advisory) — `ponytail-review` at ultra: one finding (delete the committed `opensource` symlink). No other reinvention of stdlib / unnecessary abstraction; the implementation faithfully mirrors the proven reviewer seam. See Findings → Advisory.
- [PASS] J5 UAT gaps — see UAT hand-off list.

## Findings

### Blocking (→ REQUEST_CHANGES)

- `opensource` (repo root, new symlink, mode 120000): committed dead artifact. **Why it blocks** — (1) out-of-scope: absent from the PRD file map (D3); (2) contradicts the implementer's own decision `01-implementer-ponytail-test-env.md` which asserts it "never enter[s] the commit" and that "the commit contains only the four real source files" (D7); (3) it is a dangling absolute-host-path symlink (`/workspace/opensource`) that breaks on any non-host clone/CI; (4) it is unused — every driver/test path uses the absolute `/workspace/opensource/ponytail/skills` path. Fix: drop the tracked `opensource` symlink from the commit; if the untracked env bootstrap is still wanted for the bare-worktree sweep, add a gitignore rule that also matches the symlink (`opensource` or `opensource*`) so it stays untracked, and amend the commit to contain only the four real source files.

### Advisory (consider / over-engineering)

- `opensource`: L1: `delete` committed symlink — unused dead artifact that breaks on other clones. `replacement`: remove from commit; rely on the absolute `/workspace/opensource` path (and keep any symlink untracked via a corrected gitignore pattern).
- Report/sweep accuracy: the "full suite sweep green (34/34)" acceptance is not reproducibly green — `test-implementer-driver` is 33/34 without the gitignored `workspace-portability/workspace_restore_manifest.json`. Pre-existing environmental issue (fails at base too), but the archived report should state the real, reproducible count rather than 34/34.

## Ponytail debt (harvested from changed files)

No `ponytail:` debt markers in the changed files (`bin/implementer-run.sh`, `bin/test-implementer-driver.sh`, `config/implementer.json`, `.pi/agents/implementer.md`).

## UAT hand-off list

- **Blocking**: remove the tracked `opensource` symlink from the commit (amend so the diff contains only the four PRD-mapped files); correct `.gitignore` so any env-bootstrap symlink stays untracked, and confirm the review-driver Test 7 (`opensource/ponytail/skills/...`) still passes on a real host with a live `opensource` checkout.
- Verify `test-implementer-driver.sh` returns **34/34** on a host where the gitignored `workspace-portability/workspace_restore_manifest.json` exists (the implementer's environment), and reconcile the archived report's stated count.
- Confirm the full factory sweep is green in the deliverer's real environment: implementer (34), review (61), factory-run (22), merge-pr (8), transition (45).
- On a real host, confirm the pi invocation in `run_container()` positions the six `--skill` flags between the session args and the brief/persona append, exactly as in `review-run.sh` (~506-510), and that `PONYTAIL_DEFAULT_MODE=ultra` reaches the container env file with no GH tokens.
- Review `.pi/agents/implementer.md`'s rewritten ponytail section reads correctly when the six skills are loaded and still conveys all five factory binding rules to the model.
