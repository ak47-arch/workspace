# Implementer REVISION Report — implementer-ponytail

- **PR**: ak47-arch/workspace#2 (branch `factory/implementer-ponytail/20260814-212431`)
- **Task**: implementer-ponytail · **Impl session UUID** (reused, decision 08): 8483b243-ad9a-4e00-be82-0cdf26a8801d
- **Date**: 2026-08-14
- **Review authority**: `/sandbox/review/report.md` + `/sandbox/review/decisions/01-implementer-ponytail-vanishing-scope.md`

## Revision scope

This revision fixes **exactly** the review's single **blocking** finding: restore
the factory binding rules **"say no to vanishing scope"** and **"verify what you
build"** in the implementer persona so US4's done-condition ("every factory
binding rule still appears") and decision D5 ("vanishing scope stays in the
persona") are met. Advisory items were left untouched (the `local pony=()`
indirection is retained because D1 mandates mirroring `review-run.sh`; the
`flag count` debug echo is harmless and optional). No other scope changes.

## What changed (and evidence)

### Blocking fix — `.pi/agents/implementer.md`
Restored the two factory binding rules as explicit **binding-rule bullets** in the
"Factory-worker rules (binding)" section:
- Rule 6: **Verify what you build.** Run the PRD's verification commands; if code
  won't run in the sandbox, prove what can be proven (syntax, static, unit) and
  record what remains for UAT.
- Rule 7: **Say no to vanishing scope.** If a story is genuinely ambiguous or
  unresolvable without the user, implement the deterministic best interpretation,
  mark it in the report as a UAT hand-off, and move on.

Evidence: `grep -n "vanishing scope\|unresolv\|ambiguous" .pi/agents/implementer.md`
now finds the rule (lines 69–70); `grep -n "Verify what you build"` finds the
re-affirmed binding bullet (line 66). The persona's "Working style: ponytail
(loaded as real skills)" section still references all six loaded skills.

### Redundancy mirror (review finding names this file) — `.agents/skills/implementer-ops/SKILL.md`
The review's blocking finding explicitly lists this file as dropping the rule
("grep for `vanish`/`unresolv`/`ambiguous` finds nothing in the persona or the
ops skill"), and the review decision sanctions mirroring the vanishing-scope rule
in the run contract "for redundancy". Added both rules to the "## 4. Hard rules
(non-negotiable)" section:
- **Verify what you build** — run the PRD's verification commands; prove what can
  be proven and record exactly what remains for UAT.
- **Say no to vanishing scope** — if a story is genuinely ambiguous or
  unresolvable without the user, implement the deterministic best interpretation,
  mark it in the report as a UAT hand-off, and move on.

Evidence: `grep` now finds `vanishing scope` (lines 61–62) and `Verify what you
build` (line 59) in the skill.

## Per-story status (re-confirmed)

- **US1 config — PASS** (unchanged): `ponytail` block + `PONYTAIL_DEFAULT_MODE` in
  `env_allowlist`; JSON parses.
- **US2 driver config reads + env file — PASS** (unchanged): `cfg` reads +
  fallbacks; `write_env_file()` emits `PONYTAIL_DEFAULT_MODE=%s`; token-free
  invariant holds (asserted).
- **US3 six `--skill` flags — PASS** (unchanged): six flags injected between
  session args and persona append; smoke asserts all six under the live skills
  dir (flag count = 6).
- **US4 persona — NOW PASS**: all factory binding rules appear — no-git (rule 3),
  brief/outbox (Completion + ops contract), **verify what you build (rule 6)**,
  **say no to vanishing scope (rule 7)** — plus the six loaded-skill references.
- **US5 tests — PASS** (unchanged): env-file assertion + mocked-podman smoke via
  `IMPLEMENTER_PODMAN_BIN`; all six new assertions green.

## Verification results

Ran inside `/sandbox/worktree`:

- **AC1 — syntax/JSON**: `bash -n bin/implementer-run.sh` → **exit 0**;
  `config/implementer.json` parses via `python3 json.load` → **exit 0**. `jq`
  deferred (not installed in this container; verified by file inspection + JSON
  parse).
- **AC2 — `bash bin/test-implementer-driver.sh`** → **33 passed, 1 failed**. The
  single failure is the pre-existing **environmental** `resolve_repo MANIFEST_BRANCH
  = 'master' — expected public-release` (fixture `cp`s the gitignored host artifact
  `workspace-portability/workspace_restore_manifest.json`, absent from a bare
  clone). **All six ponytail assertions PASS** (see below).
- **AC3 — full sweep** (matches the review's recorded status):
  - `test-implementer-driver`: **33/34** (1 env manifest fail — pass on real host)
  - `test-review-driver`: **60/61** (1 env `opensource` fail — Test 7 requires the
    live `opensource` checkout, deliberately absent per review-sanctioned symlink
    drop — passes on a real host)
  - `test-factory-run`: **22/22** (exit 0)
  - `test-merge-pr`: **8/8** (exit 0)
  - `test-transition-task`: **45/45** (exit 0)
- **Six new ponytail assertions — ALL PASS**:
  `env file forces PONYTAIL_DEFAULT_MODE=ultra`, `env file excludes GITHUB_TOKEN`,
  `main executes end-to-end under --dry-run (exit 0)`, `smoke: six ponytail
  --skill flags from the live skills dir` (flag count = 6), `smoke:
  PONYTAIL_DEFAULT_MODE=ultra carried to the container`, `smoke: env file carries
  no GitHub token`.
- **AC4 — grep proof**: `${pony[@]}` between session args and brief append;
  `write_env_file()` emits the mode line. (Unchanged from original run.)
- **AC5 — persona (US4) — NOW PASS**: references the six loaded skills **and**
  retains every factory binding rule, including the restored "verify what you
  build" and "say no to vanishing scope".

**jq note**: `jq` is not installed in this sandbox, so the driver exercised the
non-jq fallback path (`PONYTAIL_SKILLS_DIR=/workspace/opensource/ponytail/skills`,
`PONYTAIL_DEFAULT_MODE=ultra`); config and fallback resolve to identical values,
so acceptance is unaffected.

## UAT hand-off list

1. **Confirm the blocking fix reads correctly** in `.pi/agents/implementer.md`:
   "verify what you build" (rule 6) and "say no to vanishing scope" (rule 7) are
   explicit binding-rule bullets alongside the six loaded-skill references.
2. **Confirm the `implementer-ops` redundancy mirror** in
   `.agents/skills/implementer-ops/SKILL.md` Hard-rules section.
3. **Re-run `test-implementer-driver.sh` and `test-review-driver.sh` on a real
   host** (with the live `opensource` checkout + gitignored
   `workspace_restore_manifest.json`) → expect 34/34 and 61/61 (the two
   environmental checks cannot pass in a bare clone).
4. **Confirm `jq`-based `cfg` reads** on a host where `jq` is installed.
5. **Confirm the real container `pi` invocation** carries all six `--skill` flags
   and `PONYTAIL_DEFAULT_MODE=ultra` reaches the env file with no GH tokens.

## Decisions emerged (revision)

- `outbox/decisions/02-implementer-ponytail-restore-vanishing-scope.md` — records
  the implementation of the review's blocking fix (restoring the two binding
  rules to the persona + ops contract).
- Note: the original run's `01-implementer-ponytail-test-env.md` (gitignored env
  bootstrap) is **superseded** — revision-1 deliberately dropped the `opensource`
  symlink and manifest copy per the review-sanctioned scope-correction; that
  decision is retained only as historical record.
