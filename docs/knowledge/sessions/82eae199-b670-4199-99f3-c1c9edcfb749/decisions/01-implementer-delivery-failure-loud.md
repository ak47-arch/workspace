## Decision: Explicit guard + return discipline for delivery failures

**Status**: accepted
**Date**: 2026-08-17
**Task**: [implementer-delivery-failure-loud](../../../../tasks/implementer-delivery-failure-loud.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Use the explicit if ! push_and_pr guard and add explicit failure returns inside push_and_pr for the push and gh pr create steps.

### Context

The implementer driver's success path called `push_and_pr || true`, which
swallowed delivery failures (branch push rejection, `gh pr create` failure) and
still printed `Done (exit 0)`. The fix must route a failed delivery into the
existing `fail_run` path. `set -euo pipefail` is active in the script.

### Problem

Correctly wiring a non-zero delivery outcome into `fail_run` is subtle:
`push_and_pr` is invoked from an `if ! …` guard, and calling a function from an
`if`/`!` condition **disables `errexit` for that function's body** in bash.
Consequently `push_and_pr` must enforce its own failure discipline via explicit
`return` statements — it cannot rely on `set -e` to abort, because errexit is
suspended while the guard evaluates the function's exit status.

### Alternatives

1. **No guard, rely on `set -e` alone** — an unguarded failing `push_and_pr`
   would make the script abort with a bare exit code before `fail_run` runs (no
   `FAILED:` message, no report, no task revert). Rejected (matches the PRD's
   guard-placement note).
2. **Guard only, no in-function returns** — `if ! push_and_pr; then fail_run…`
   with the old body. But the old body continued past a failed `git push`,
   printing a misleading `Pushed branch …`, so the function's exit status could
   still be 0 after a real delivery failure. Rejected.
3. **Guard + explicit in-function returns (chosen)** — `if ! push_and_pr; then
   fail_run "delivery failed: branch push or PR creation"; fi`, with `git push`
   and `gh pr create` each wrapped to `echo` an error and `return 1` (and the
   existing commit error already `return 2`). This makes the function's exit
   status truthful regardless of errexit state, so the guard sees exactly one
   delivery outcome.

### Decision

Use the explicit `if ! push_and_pr` guard and add explicit failure returns
inside `push_and_pr` for the push and `gh pr create` steps. Route failures to
the existing `fail_run` with reason `delivery failed: branch push or PR
creation`, which reverts the task to `prd-ready`, archives the partial report,
and exits 1.

### Rationale

- The `if !` guard is required under `set -e` (an unguarded failing call aborts
  before `fail_run` runs).
- Since the `if !` guard suspends errexit inside the function body, the explicit
  returns are the only reliable mechanism to make a failed push/PR surface as a
  non-zero function status. This eliminates the misleading `Pushed branch …` /
  `PR raised …` output after a failed delivery.
- Reuses `fail_run` (revert-to-prd-ready + archive) exactly as specified — no
  new lifecycle machinery.

### Consequences

- Delivery failures now fail loudly: non-zero exit, clear `FAILED:` reason, task
  reverted to `prd-ready`, partial report archived.
- A push that succeeds but `gh pr create` fails leaves the branch on the remote
  and reverts the task (the PRD's re-run guidance applies).
- Scope constrained to `bin/implementer-run.sh`; `bin/review-run.sh`'s
  `post_pr_comment || true` pattern is deliberately left untouched (out-of-scope
  follow-up).

### Revision triggers

- If a future change calls `push_and_pr` from a context where errexit is NOT
  suspended (e.g. not inside a condition), re-evaluate whether the explicit
  returns remain necessary or could be simplified.
- If the reviewer pattern (`post_pr_comment || true`) is addressed in a
  follow-up, consider whether the two drivers should share a common guard
  helper.
