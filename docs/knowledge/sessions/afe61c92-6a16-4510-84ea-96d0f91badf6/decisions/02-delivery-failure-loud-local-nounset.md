## Decision: Initialize push_and_pr locals to avoid bash set -u crash

**Status**: accepted
**Date**: 2026-08-17
**Task**: implementer-delivery-failure-loud
**Project**: software-factory
**Session**: sessions/afe61c92-6a16-4510-84ea-96d0f91badf6/session.jsonl

### Context

Under `set -euo pipefail` (the driver's shebang), bash 5.2 treats a bare
`local pr_url` (no value) as leaving the variable **unset** for expansion
purposes. The `push_and_pr()` PR-creation retry loop in `bin/implementer-run.sh`
declared `local pr_url` bare and then guarded on `[ -z "$pr_url" ]`.

### Problem

Expanding an unset local under `set -u` aborts the script with
`pr_url: unbound variable` at the loop guard — which, once the delivery guard
(`if ! push_and_pr; then fail_run …`) routes failures through the function,
would crash the driver *before* `fail_run` ran (no FAILED message, no revert,
no exit 1), re-creating a silent-failure mode. The failure surfaced while adding
the failing-PR-create delivery test.

### Alternatives

- **A. `local pr_url=""`** (chosen): assigns an empty value, so the variable is
  bound for `set -u` expansion regardless of bash version.
- **B. `local pr_url=`** — equivalent; slightly less explicit.
- **C. `local pr_url; pr_url=""`** — same effect, two statements, no benefit.

### Decision

Initialize explicitly to empty: `local pr_url=""`, with a comment explaining the
`set -u`/bash-5.2 rationale so it is not "cleaned up" later.

### Rationale

Smallest change that makes the delivery failure path robust against an
unbound-variable abort; follows the codebase's existing convention elsewhere
(e.g. `local attempt=0`, `local exit_code=0`).

### Consequences

- The failing-PR-create path now reaches `fail_run` and reports truthfully.
- No behavior change for real `gh pr create` runs (the assignment `pr_url="$(…)"`
  still supplies the value on success).

### Revision triggers

- If the driver drops `set -u`, the guard may be reverted to a bare `local`
  (not recommended).