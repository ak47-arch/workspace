## Decision: Multi-repo associative arrays use `declare -gA` (source-scope survival)

**Status**: accepted
**Date**: 2026-08-18 17:30
**Task**: multi-repo-delivery-bookkeeping-prs
**Project**: software-factory
**Session**: sessions/c63649d5-f660-4494-af41-d0025d02f728/session.jsonl

### Context
The implementer driver's new multi-repo state (`REPO_PATH`, `REPO_LOCAL`,
`REPO_MANIFEST_BRANCH`, `REPO_WORKTREE`, `REPO_BRANCH`, `REPO_SHA`, `REPO_PR`,
`REPO_VERDICT`, `REPO_STATE`, `REPO_DIRTY`) is declared at the driver's top level.
The fixture-based test harness sources the driver from *within* a function
(`source_driver() { source "$DRIVER"; set +e; }`).

### Problem
A plain `declare -A` executed inside a file that is sourced from within a function
scopes the variable to that function; the array disappears when `source_driver`
returns (manifesting as `declare: REPO_PATH: not found` and an "unbound variable"
error under `set -u`). Plain assignments (`REPO_KEYS=()`, `MULTI_MODE=false`)
survive because they create globals, but `declare -A` does not.

### Alternatives
- `declare -gA` — global associative arrays regardless of source context.
- Re-declare the arrays at every call site.
- Only use plain indexed arrays/strings (avoids associative arrays entirely).

### Decision
Use `declare -gA REPO_PATH REPO_LOCAL ...` so the associative arrays are always
global, whether the driver runs as a top-level script or is sourced from within a
test harness function.

### Rationale
- Keeps the natural per-key map representation (key → repo) without clobbering.
- Survives the existing test harness pattern with zero test-side changes.
- Matches how the driver's other state (plain assignments) already behaves.

### Consequences
- The arrays persist across `source_driver` calls and between driver functions.
- `resolve_repo_set` / `prepare_run_dirs_multi` / `deliver_multi` share one global
  repo-set state, simplifying the per-repo delivery loop.

### Revision triggers
- If the driver is ever refactored to avoid sourcing-from-a-function (then `declare
  -A` at top level would suffice).
