# Code Review

- Reviewed: ak47-arch/workspace#2 (repo: workspace, PR #2)
- Task: implementer-ponytail · PRD: docs/prd-queue/2026-08-14-implementer-ponytail.md · Review session: 6b560fbb-bfe9-450b-94f9-fb24d8dadcec
- Base: 86363fd55b2adb5098f7826fe62cd6f019e16f89 → Head: 2e4aa94623f17c089feb37dcaa0cfc3920f3fbd2

## Verdict

**APPROVE** — the diff implements all five stories and every PRD acceptance check either passed in-sandbox or is a documented, pre-existing/environmental failure (missing gitignored checkout artifacts, absent jq). Scope is clean, D1's "mirror review-run.sh" is honored exactly, and the review's previous blocking finding (restored binding rules, remove committed `opensource` symlink) is resolved.

## Verification results

(Ran inside `/sandbox/worktree` on the PR head.)

- **AC1 — syntax/JSON**: `bash -n bin/implementer-run.sh` → **exit 0**. `python3 -m json.tool config/implementer.json` → **exit 0** (JSON parses).
- **AC2 — `bash bin/test-implementer-driver.sh`** → **ran, 33 passed / 1 failed**. The single failure is pre-existing/environmental: `resolve_repo MANIFEST_BRANCH = 'master' — expected public-release` — the fixture `cp`s the gitignored host artifact `workspace-portability/workspace_restore_manifest.json` (absent from a bare checkout). `resolve_repo` and the test byte-identical at base. **All six new ponytail assertions PASS** (env file forces ultra; token-free; main executes end-to-end under `--dry-run` vs mock podman; six `--skill` flags from live skills dir, flag count = 6; `PONYTAIL_DEFAULT_MODE=ultra` carried to container; no GitHub token).
- **AC3 — full suite sweep** (ran):
  - `test-implementer-driver` → **33/34** (1 env-manifest fail, documented below)
  - `test-review-driver` → **60/61** (1 env fail: `opensource/ponytail/skills` dir absent from checkout root; review files out-of-scope for this PR; passes on a host with the live checkout — sanctioned by decision 01)
  - `test-factory-run` → **22/22, exit 0**
  - `test-merge-pr` → **8/8, exit 0**
  - `test-transition-task` → **45/45, exit 0**
- **AC4 — grep proof**: `${pony[@]}` injected between session args and brief append (`implementer-run.sh:421-422`); `write_env_file()` emits `PONYTAIL_DEFAULT_MODE=%s` (`:346`); all six skill names present; config `jq '.env_allowlist[]'` — **deferred** (jq not installed in this container); verified structurally via `python3` (both `PONYTAIL_DEFAULT_MODE` in allowlist and `ponytail` block correct). The driver's jq-less fallback resolves to identical values.
- **AC5 — persona (US4)**: references the six loaded skills **and** retains every factory binding rule (no-git #3, verify #6, vanishing-scope #7, brief/outbox, no-secrets #2). **PASS.**

## Story-by-story

- [PASS] **US1 config** — `config/implementer.json` gains `ponytail` block (`skills_dir` + `default_mode: ultra`) and `PONYTAIL_DEFAULT_MODE` in `env_allowlist`. Evidence: JSON (verified via `python3`), jq enumeration deferred (jq missing).
- [PASS] **US2 driver config reads + env file** — `cfg '.ponytail.skills_dir'` / `'.ponytail.default_mode'` reads + jq-less fallbacks (`implementer-run.sh:57-58`, `71-72`); `env_allowed()` fallback gains `PONYTAIL_DEFAULT_MODE` (`:88`); `write_env_file()` emits the mode line but still excludes GH tokens (`:344-351`). Test asserts both inclusion and token-free invariant.
- [PASS] **US3 six `--skill` flags** — `PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help)` + `ponytail_skill_flags()` seam (`:356-361`); injected via `${pony[@]}` between session args and persona append (`:421-422`); resolves under `/workspace/opensource/ponytail/skills`. Smoke proved all six in the podman invocation (flag count = 6). Mirrors `review-run.sh` exactly.
- [PASS] **US4 persona prose → loaded-skills pointer** — `.pi/agents/implementer.md` "Working style: ponytail (loaded as real skills)" references all six loaded skills; the factory binding rules (incl. no-git, verify, vanishing-scope) retained as explicit binding bullets (rules 6-7 restored). Evidence: sed read-out of lines 25-70.
- [PASS] **US5 tests** — env-file assertion (`PONYTAIL_DEFAULT_MODE=ultra` present, token-free) + mocked-podman end-to-end smoke via new `IMPLEMENTER_PODMAN_BIN` seam executing driver `main` under `--dry-run`, asserting all six `--skill` flags + ultra mode. All assertions pass; full suite sweep green (33/34 env excl.).

## Deterministic checks

- [PASS] **D1 PR metadata sane** — branch `factory/implementer-ponytail/20260814-212431` (from report) / tag `**Status**: Final` PRD; base `86363fd` + head `2e4a946` exist; diff non-empty (6 files, 213+/31-), scoped.
- [PASS] **D2 Worktree clean / read-only** — `git status` clean at head `2e4aa94`; reviewer made no git mutations (read-only).
- [PASS] **D3 Scope containment** — all 6 changed files fall within PRD file map + two justified extras: `.gitignore` (`opensource` bare-symlink pattern — sanctioned by decision 01, prevents re-committing the out-of-scope symlink) and `.agents/skills/implementer-ops/SKILL.md` (redundancy mirror of the two restored binding rules, review-sanctioned). No stray deps, no unrelated refactors.
- [PASS] **D4 Scope ⊆ PRD file-map** — every claimed file present: `config/implementer.json`, `bin/implementer-run.sh`, `.pi/agents/implementer.md`, `bin/test-implementer-driver.sh` all in the diff; bookkeeping files not hand-edited. Nothing promised missing.
- [PASS] **D5 Story → diff coverage** — each voiceability maps to concrete hunks (US1 config, US2 env/write_env, US3 flags/injection, US4 persona, US5 tests). No story implemented without a story, no story unimplemented.
- [PASS] **D6 No secrets / stray deps** — diff grep for real secrets yielded only allowlist/test-token references; no `package.json`/`requirements`/`Gemfile`/`go.mod` new deps added. Env file test asserts `GITHUB_TOKEN` excluded.
- [PASS] **D7 Implementer report matches diff** — archived `docs/implementations/2026-08-15-implementer-ponytail/revision-2-report.md` matches actual diff: all stories present, all six assertions green, two environmental suite failures correctly attributed, `.gitignore` + ops-skill extras explained, verification claims match what I re-ran. No dropped work.

## Judgment checks

- [PASS] **J1 Story intent** — observables hold: config reads populate env file + pi flags at runtime; mocked-podman smoke executes the real `main` (`--dry-run`) and proves the flags land in the actual podman invocation.
- [PASS] **J2 PRD-decision conformance** — D1 (mirror review-run) honored (identical skill names, seam shape, config keys/fallbacks, env line, injection position, `podman_call()` wrapper); D2 (live read-only checkout, no vendoring) honored; D3 (`IMPLEMENTER_PODMAN_BIN` seam, `exec` dropped for the function seam) honored; D4 (ultra mode) honored; D5 (binding rules stay in persona) honored.
- [PASS] **J3 Edge / error paths** — jq-less fallbacks handle missing jq; env file conditionally emits mode only when set; container force-rm + stop use the seam with `|| true`; mock podman fabricates the report so the success path completes. Test suite covers env + cleanup + smoke paths.
- [PASS] **J4 Ponytail over-engineering pass (ultra)** — see Advisory findings; the pass is essentially lean because D1 mandates mirroring the reviewed `review-run.sh`, and the only indirections present are the D1-mandated ones. Net: `net: 0 lines` row considered — driven by hard mirror contract, so no mandatory cuts.
- [PASS] **J5 UAT gaps** — enumerated in UAT list; the two env-specific suite checks + real-container invocation + jq path are the only unverifiable-in-sandbox items.

## Findings

### Blocking (→ REQUEST_CHANGES)

None.

### Advisory (consider / over-engineering)

- `bin/implementer-run.sh:L378-379`: `local pony=()` + `while read ... pony+=($flag)` round-trips `ponytail_skill_flags` output into an array only to re-splat it. Could build the array directly or reuse flag generation inline. **Retained by D1** ("mirror review-run.sh exactly") — advisory only, not blocking (the reviewer's own `review-run.sh:474` uses the same pattern).
- `bin/test-implementer-driver.sh` (mock podman): `fantasy` seam parses `-v` args to locate the `/sandbox` host dir — reasonable for an end-to-end smoke; a simpler alternative would pass the run-dir via env, but the parse keeps the mock opaque to the driver. Advisory.
- Test-only debug echo `smoke: flag count = ...` (`>&2`) in the six-flags assertion is optional/harmless diagnostic. Advisory.

## Ponytail debt (harvested from changed files)

No `ponytail:` shortcut markers found in any changed file. No open debt to ledger.

## UAT hand-off list

1. **Re-run the two environmental suites on a real host** (with the live `opensource/` checkout + gitignored `workspace-portability/workspace_restore_manifest.json`): expect `test-implementer-driver` **34/34** and `test-review-driver` **61/61** — the two documented failures (env manifest + skills-dir check) cannot pass in this bare sandbox checkout.
2. **Confirm `jq`-based `cfg` reads + `.env_allowlist[]` enumeration** on a host where `jq` is installed (deferred here — jq not present; verified structurally via `python3`; jq-less fallback resolves identically).
3. **Confirm a real container `pi` invocation** carries all six `--skill` flags under `/workspace/opensource/ponytail/skills` and that `PONYTAIL_DEFAULT_MODE=ultra` reaches the container env file with no GH tokens (mock-podman smoke proves format; real runtime not exercised without podman).
4. **Verify the persona binding rules read correctly** in `.pi/agents/implementer.md`: rules 6 ("verify what you build") and 7 ("say no to vanishing scope") are explicit binding bullets alongside the six loaded-skill references.
5. **Confirm the `.gitignore` bare-`opensource` correction** is acceptable (matches decision 01) and that gitignored bootstrap artifacts (`workspace-portability/`, `opensource`) remain untracked.
6. User inspection: the six-skill persona phrasing maps skill names to discipline duties — confirm the phrasing reads as intended for the implementer persona.