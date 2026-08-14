## Decision: Code-review agent APPROVED PR #1, but a real host run surfaced 3 driver bugs the in-container review could not see

- Slug: code-review-agent · Review session: 19cb853b-a2e9-4eb6-865a-138864ba1934
- Date: 2026-08-14
- Status: accepted (operator observation from the first dogfood run of the review agent)

### Context

First dogfood on PR #1 (code-review-agent). The review worker (inside `sandbox:latest`,
read-only) returned **APPROVE** with 50/50 unit pass, no blocking findings — every
deterministic/judgment check green. But when the host driver actually ran
(`bin/review-run.sh 1`), it crashed three times on real-path defects that the review
did **not** flag:

1. `bin/review-run.sh:684` — `echo "dry-run: $DRY_RUN"` referenced `$DRY_RUN` **before**
   init at line 688, crashing under `set -u` (exit 2). Hidden because the reviewer's
   suite sources the driver (`REVIEWER_RUN_SOURCED=1`) so `main` never runs, and
   `bash -n` can't see an unbound-var-at-runtime.
2. `pr_metadata()` used `gh pr view --json baseRefOid` — **not a valid gh field** in the
   installed gh; base SHA must come from `gh api .../pulls/<n> --jq .base.sha`. Hidden
   because the mock `gh` in `test-review-driver.sh` fabricates a `baseRefOid` and has no
   `api` case — a test-reality gap.
3. `local verdict` at top level — `local` outside a function is a hard error. Hidden for
   the same reason as #1 (main never runs under source-from-test).

All three fixed in the working tree before the successful re-run.

### Problem

The review agent verified the PR by (a) reading the code + report and (b) running the
PRD verification suite **with a mocked `gh` and without executing the driver's `main`**.
Real driver behavior — the exact code path that decides whether the review tool works —
was never actually executed by the review, so three runtime defects shipped past a
"clean APPROVE". This is a **simulation blind spot**: the in-container review cannot run
the host driver (no podman/gh/credential), so it trusts the unit suite + mock, and the
mock is not faithful to real `gh` nor does it exercise `main`.

### Decision

Treat an in-container APPROVE as **necessary but not sufficient**; the host-side UAT
hand-off list (item 1: real container run + real `gh`) is the authority that catches
real-path defects. Record the three fixes as the canonical driver corrections.
Possibly strengthen later (not now): an in-suite end-to-end smoke that runs the driver's
`main` (not just sources it) against a fixture with a faithful `gh` mock. Do not treat
mock-green as real-green.

### Consequences

- The review verdict (APPROVE) stands as written PR-checks + simulation, but the report
  under-claimed confidence: three real defects existed at head. The UAT hand-off list
  item #1 is exactly where they surfaced.
- The three corrections must be carried forward into whichever branch/PR hosts the
  driver (see reconciliation — implementation also currently landed on master via the
  operator's staged checkout racing the transition commit; that is a separate process
  deviation flagged for the user's call).
- Future review runs should state in the report's verification section that "driver
  `main` + real `gh`/podman were NOT exercised in-container" (they are host-UAT items).

### Revision triggers

- Add an in-suite end-to-end smoke that executes the driver `main` against a faithful
  `gh` mock → shrinks the blind spot.
- If the driver is later run headlessly by CI, the in-container gate becomes moot and
  the blind spot disappears.
