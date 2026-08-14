# Code Review

- Reviewed: ak47-arch/workspace#2 (repo: ak47-arch/workspace, PR #2)
- Task: implementer-ponytail · PRD: docs/prd-queue/2026-08-14-implementer-ponytail.md · Review session: 85f5ce0b-7de4-4230-9f17-151742cac9b9
- Base: 86363fd55b2adb5098f7826fe62cd6f019e16f89 → Head: 20c84acbf6fd24f0f74c804513e72a8b900570ec

> Note: the brief's PRD path (`/home/anupam/Desktop/workspace/docs/prd-queue/...`) does not
> exist in the sandbox; the PRD was reviewed from the authoritative read-only
> `/workspace/docs/prd-queue/2026-08-14-implementer-ponytail.md` (identical to the
> worktree copy at `/sandbox/worktree/docs/prd-queue/...`).

## Verdict
REQUEST_CHANGES — US4 / decision D5 not fully conformant: the persona drops the
"say no to vanishing scope" factory binding rule entirely and demotes "verify what
you build" out of the binding-rule prose, failing the US4 done-condition ("every
factory binding rule still appears"). Everything else (US1–US3, US5, driver wiring,
test suite) is PASS; the single blocking fix is to restore the vanished binding rules
in `.pi/agents/implementer.md` (and/or the `implementer-ops` contract).

## Verification results
Ran inside `/sandbox/worktree` (read-only review; commands executed from the PR head checkout).

- **AC1 — syntax/JSON**: `bash -n bin/implementer-run.sh` → **ran, exit 0**. `config/implementer.json`
  parses via `python3 -c "json.load(...)"` → **ran, exit 0**. `jq`-based parse **deferred** (jq not
  installed in this container); `env_allowlist[]`/`ponytail` block verified by direct inspection of the
  file instead. **PASS**.
- **AC2 — `bash bin/test-implementer-driver.sh`** → **ran, exit 1**: **33 passed, 1 failed**. The single
  failure is the pre-existing environmental `resolve_repo MANIFEST_BRANCH = 'master' — expected
  public-release` (it `cp`s the gitignored host artifact `workspace-portability/workspace_restore_manifest.json`,
  absent from a bare clone — confirmed by `cp: cannot stat .../workspace_restore_manifest.json` in the output;
  not introduced by this PR). **All six new ponytail assertions PASS**: `env file forces PONYTAIL_DEFAULT_MODE=ultra`,
  `env file excludes GITHUB_TOKEN`, `main executes end-to-end under --dry-run (exit 0)`,
  `smoke: six ponytail --skill flags from the live skills dir` (flag count = 6),
  `smoke: PONYTAIL_DEFAULT_MODE=ultra carried to the container`, `smoke: env file carries no GitHub token`.
- **AC3 — full sweep (ran, all non-environmental green)**:
  - `test-implementer-driver`: **33/34** (1 env manifest fail, above).
  - `test-review-driver`: **60/61** — single failure `ponytail skills dir not found at
    /sandbox/worktree/opensource/ponytail/skills` (Test 7 requires a live `opensource` at the checkout root;
    the direct, documented consequence of the review-mandated symlink drop — accepted by binding decision
    `01-implementer-ponytail.md`; passes on a real host).
  - `test-factory-run`: **22/22** (exit 0).
  - `test-merge-pr`: **8/8** (exit 0).
  - `test-transition-task`: **45/45** (exit 0).
- **AC4 — grep proof**: `${pony[@]}` (six `--skill` flags) sits between `"${sess_args[@]}"` and
  `--append-system-prompt /sandbox/brief.md` in `run_container()` (implementer-run.sh ~420), mirroring
  `review-run.sh` ~506-510; `write_env_file()` emits `PONYTAIL_DEFAULT_MODE=%s` (implementer-run.sh ~346).
  **PASS**.
- **AC5 — persona (US4)**: references the six loaded skills ✓ and keeps no-git + brief/outbox ✓, but
  **"say no to vanishing scope" is absent** and "verify what you build" is no longer a binding-rule bullet
  (only an ops-contract "run verification" mention). **PARTIAL / FAIL** — see blocking finding.

## Story-by-story
- **US1 config — PASS**: `config/implementer.json` has `"ponytail": { "skills_dir": "/workspace/opensource/ponytail/skills", "default_mode": "ultra" }`
  (lines 31-34) and `PONYTAIL_DEFAULT_MODE` added to `env_allowlist` (line 24). jq `cfg('.env_allowlist[]')`
  enumeration deferred (no jq), verified by file inspection + JSON parse.
- **US2 driver config reads + env file — PASS**: `cfg '.ponytail.skills_dir'`/`'.ponytail.default_mode'` reads
  with non-jq fallbacks (lines 57-58 / 72-73), fallback `env_allowed()` gains `PONYTAIL_DEFAULT_MODE` (line 88),
  `write_env_file()` emits the mode line (line ~346). Smoke asserts `PONYTAIL_DEFAULT_MODE=ultra` in the env file
  and token-free invariant (no `GITHUB_TOKEN`).
- **US3 six `--skill` flags — PASS**: `PONYTAIL_SKILL_NAMES=(ponytail ponytail-review ponytail-audit ponytail-debt
  ponytail-gain ponytail-help)` + `ponytail_skill_flags()` emit `--skill <dir>/<name>`; injected via `${pony[@]}`
  between session args and brief append. Mocked-podman smoke asserts all six flags resolve under the live
  `/workspace/opensource/ponytail/skills` dir (flag count = 6).
- **US4 persona prose → loaded-skills pointer — FAIL**: the section references the six loaded skills and
  preserves no-git (rule 3) + brief/outbox, but **"say no to vanishing scope" is dropped** from both
  `.pi/agents/implementer.md` and `.agents/skills/implementer-ops/SKILL.md`, and "verify what you build" is
  demoted from a binding-rule bullet to an ops-contract "run verification" mention (line 73). The US4
  done-condition ("every factory binding rule still appears") is not met.
- **US5 tests — PASS**: env-file assertion (ultra mode + token-free) and mocked-podman `--dry-run` smoke
  (via `IMPLEMENTER_PODMAN_BIN`) both present and green in the run.

## Deterministic checks
- [PASS] **D1 metadata sane** — branch `factory/implementer-ponytail/20260814-212431`; base/head SHAs both
  resolve; diff non-empty, scoped to 5 files. Two commits (rev0 + revision-1).
- [PASS] **D2 worktree clean / read-only** — `git status` clean at HEAD `20c84ac`; reviewer made no changes
  (re-verified clean after running tests).
- [PASS*] **D3 scope containment** — 4 of 5 changed files match the PRD file map. `.gitignore` is an
  **exception**: it is a documented scope-correction mandated by the binding review decision
  `01-implementer-ponytail.md` (fix the directory-only `opensource/` pattern so a bare `opensource` symlink is
  ignored). The `opensource` symlink added in rev0 was deleted in revision-1 (net absent from the diff; confirmed
  `git ls-files`/`ls` show none). Sanctioned, non-blocking.
- [PASS] **D4 scope ⊆ PRD file-map** — all 4 mapped source files present in the diff. Bookkeeping
  (`docs/tasks/implementer-ponytail.md`, `docs/tasks.txt`) intentionally unchanged (driver-owned
  `transition-task.sh` fires on APPROVE; the task file remains `prd-ready`, as expected pre-transition).
- [PASS] **D5 story → diff coverage** — every US maps to diff hunks; no capability beyond the stories
  (`podman_call`/`IMPLEMENTER_PODMAN_BIN` seam is D3-mandated, not speculative).
- [PASS] **D6 no secrets / stray deps** — env-file smoke proves `GITHUB_TOKEN` never enters the container env;
  no new dependencies added.
- [PARTIAL-FAIL] **D7 report matches diff** — verification counts in the revision-1 report match what I ran
  (33/34 impl, 60/61 review, 22/22, 8/8, 45/45). But the report's claim "US4 — PASS ... all five binding rules
  retained (5/5)" is **inaccurate**: "say no to vanishing scope" is absent and "verify" is demoted. Report
  overstates US4.

## Judgment checks
- [PARTIAL] **J1 story intent** — US1–3, US5 intents hold (behavior real and exercised by the smoke). US4's
  intent (keep all factory binding rules) partially fails: vanishing-scope guardrail lost.
- [PARTIAL] **J2 PRD-decision conformance** — D1 ✓ (injection position + seam shapes mirror `review-run.sh`
  exactly); D2 ✓ (absolute path, no vendoring, shared `.pi/settings.json` untouched); D3 ✓
  (`IMPLEMENTER_PODMAN_BIN` seam, `podman_call()`, `exec` dropped for the subshell); D4 ✓ (`ultra`); **D5 ✗**
  — "vanishing scope stays in the persona" violated.
- [PASS] **J3 edge / error paths** — `podman_call` sites preserve `|| true`; `write_env_file()` guards empty
  mode; smoke fixture ships `sort-knowledge-index.py` + writable `docs/knowledge/`; mock handles the `/sandbox`
  mount. No new error-path gaps.
- [PASS*] **J4 ponytail over-engineering pass (ultra)** — production wiring is lean and mirrors the proven
  review-run.sh precedent; advisory-only notes below. `net: -0 lines possible` for the production wiring (test
  additions are PRD-mandated).
- [PASS] **J5 UAT gaps** — see UAT hand-off list.

## Findings
### Blocking (→ REQUEST_CHANGES)
- `.pi/agents/implementer.md` (rewritten "Working style" section) + `.agents/skills/implementer-ops/SKILL.md`:
  the factory binding rule **"say no to vanishing scope" is dropped** (grep for `vanish`/`unresolv`/`ambiguous`
  finds nothing in the persona or the ops skill), and **"verify what you build" is demoted** from a binding-rule
  bullet to an ops-contract "run verification" mention. US4's done-condition requires "every factory binding
  rule still appears" and decision D5 requires "vanishing scope stays in the persona". This is a documented
  PRD departure with no rationale → blocks.

### Advisory (consider / over-engineering)
- `.pi/agents/implementer.md`: `L26-41` — re-state "verify what you build" and "say no to vanishing scope" as
  explicit binding-rule bullets (ties to the blocking finding; keeps the contract explicit rather than implied
  via the ops-skill reference).
- `bin/implementer-run.sh` `L380-382`: `yagni` — the `local pony=()` + `while read` array indirection could be
  `$(ponytail_skill_flags)` inlined; **keep** because D1 mandates mirroring review-run.sh (consistency wins).
- `bin/test-implementer-driver.sh`: `shrink: delete` — the `echo "  smoke: flag count = ..." >&2` debug line is
  informational only; harmless, optionally removable.

## Ponytail debt (harvested from changed files)
No `ponytail:` debt comments in any changed file (`.pi/agents/implementer.md`,
`bin/implementer-run.sh`, `bin/test-implementer-driver.sh`, `config/implementer.json`, `.gitignore`).
→ **No ponytail: debt.**

## UAT hand-off list
- **Blocking fix**: restore "say no to vanishing scope" (and re-affirm "verify what you build") in the persona's
  binding-rule prose, then re-verify US4 / re-run `test-implementer-driver.sh`.
- Confirm on a real host (with a live `opensource` checkout and the gitignored
  `workspace-portability/workspace_restore_manifest.json`): `test-implementer-driver` 34/34 and
  `test-review-driver` 61/61 — the two environmental checks that cannot pass in a bare clone.
- Confirm `jq`-based `cfg('.ponytail.skills_dir')` / `cfg('.ponytail.default_mode')` /
  `cfg('.env_allowlist[]')` reads on a host where `jq` is installed (deferred here — no jq in container).
- Confirm on a real host that the container `pi` invocation carries all six `--skill` flags and that
  `PONYTAIL_DEFAULT_MODE=ultra` reaches the container env file with no GH tokens (proven here via mock; real
  podman run remains a host/UAT check).
- Confirm the fixed `.gitignore` (`opensource`) keeps any future env-bootstrap `opensource` symlink untracked.
- Confirm the rewritten persona section reads correctly with the six skills loaded and conveys every binding
  rule (after the blocking fix).
