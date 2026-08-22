## Decision: Reviewer resolves the active `gh` lazily via a `gh_call` function so host-only gh is mockable

**Status**: accepted
**Date**: 2026-08-13 21:11
**Task**: [code-review-agent](../../../../tasks/code-review-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: bin/review-run.sh resolves the active gh at call time through a one-line function gh_call() { "${REVIEWER_GH_BIN:-gh}" "$@"; }, and every gh invocation goes through it (p

### Context

`bin/review-run.sh` mirrors `bin/implementer-run.sh`, but with one deliberate
divergence in the compliance model: the reviewer MAY run read-only git
(`diff/log/show/status`) but must NEVER run `gh` — every `gh` call is
driver-side, and the driver owns all PR comments, labels, and lifecycle
transitions (Decision 03). The driver performs four `gh` operations: resolve/`--pick`
a PR (`pr view` / `pr list`), post the review comment (`pr comment`), and tag the
outcome label (`pr edit` / `label create --force`). These must be testable in the
sandbox, which has no `gh` binary and no GitHub credential.

The implementer driver caches tool paths as plain shell variables at source time
(e.g. `CONFIG_FILE`, `WORKSPACE`), which works for git (invoked as `git` via PATH).
But a cached `GH="${REVIEWER_GH_BIN:-gh}"` variable is brittle for a mockable,
host-only tool: the value is fixed the moment the script is sourced, so a
fixture-based test that sets `REVIEWER_GH_BIN` *after* sourcing the driver (to
inject a mock) silently keeps the old value and the mock never runs.

### Problem

How does the driver invoke `gh` in a way that (a) keeps it strictly host-side and
absent from the container env, (b) is deterministically mockable by the unit suite
without a real GitHub/credential, and (c) doesn't share a croppy path-caching bug
that breaks the guardrail tests?

### Alternatives

- **Cached `GH` variable** (`GH="${REVIEWER_GH_BIN:-gh}"` at source time) — simplest,
  but mocks injected after sourcing are ignored, making the gh-call-count guardrails
  untestable. Rejected.
- **Export `REVIEWER_GH_BIN` inside `setup_fixture`** — the fixture builder runs in
  a command-substitution subshell, so its `export`s are lost to the parent; must
  instead write a `fixture.env` the test sources in the parent shell, then override
  the cached `WORKSPACE` shell var. Combined with the lazy lookup this closes the
  loop (Verified: 50/50 review-driver tests pass).
- **Never `gh` from the driver at all** — impossible: the driver must resolve the
  PR and post the comment; the PRD explicitly places all `gh` host-side. Rejected.

### Decision

`bin/review-run.sh` resolves the active `gh` at **call time** through a one-line
function `gh_call() { "${REVIEWER_GH_BIN:-gh}" "$@"; }`, and every `gh` invocation
goes through it (`pick_pr`, `pr_metadata`, `post_pr_comment`, `update_label`). The
reviewer config/test suite adds three test seams: `REVIEWER_GH_BIN` (mock gh),
`REVIEWER_WORKSPACE` + the `WORKSPACE` shell-var override (disposable fixture), and
`REVIEWER_RUNS_ROOT` / `REVIEWER_REVIEWS_ROOT` (redirect run+archive roots out of the
real home). `config/reviewer.json` carries `runs_root`/`reviews_root`, and the unit
suite installs a mock `gh` in a temp PATH/abs path that logs every invocation for
call-counting.

### Rationale

The lazy lookup keeps `gh` host-only by construction (the container gets no `gh`
and no token — enforced by `write_env_file` and test-asserted as "no GITHUB_TOKEN in
the env file") while making the driver fully unit-testable with a mocked `gh`,
mirroring the implementer's fixture-driven seam approach. Resolving at call time
(not source time) is what makes the mock takeover reliable, and it keeps the 
compliance invariant legible: `gh` exists only on the host, in one function.

### Consequences

- `bin/review-run.sh` has no cached `gh` variable; all four gh surfaces are
  `gh_call`, so swapping in a mock or a future gh alternative is a one-line change.
- The unit suite (`bin/test-review-driver.sh`, 50 tests) drives `resolve_pr`
  (`repo#num`/`owner/repo#num`/URL/bare/bare-number/`--pick`), slug, repo+PRD
  resolution, run-dir/brief contract, PR-head checkout with base fetched, archive to
  `docs/code-reviews/<date>-<slug>/`, dry-run transitions, and mock-call-counted
  comment/label — plus guardrails (no `GITHUB_TOKEN` in env, six ponytail
  `--skill`s + `PONYTAIL_DEFAULT_MODE=ultra`).
- Container runs still need a real `gh` on the host; the mock covers only the
  deterministic driver logic (documented as a UAT hand-off).

### Revision triggers

- `gh` is replaced by a different client, or gh get moved into the container — the
  `gh_call` seam is the single change point and should be revisited.
- A future config-driven check registry (deferred) or automation layers on a
  poller driving `--pick` — revisit the mockable `--pick` seam.
