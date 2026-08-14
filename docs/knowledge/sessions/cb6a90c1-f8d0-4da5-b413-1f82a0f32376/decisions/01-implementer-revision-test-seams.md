## Decision: Revision mode adds the podman/gh test seams and a stable revision number as part of this task (D8 dependency resolution)

**Status**: accepted
**Date**: 2026-08-14
**Task**: implementer-revision-mode
**Project**: software-factory
**Session**: sessions/cb6a90c1-f8d0-4da5-b413-1f82a0f32376/session.jsonl

### Context

Implementing `bin/implementer-run.sh --revise <pr>` required the mocked-podman
end-to-end smoke (US5b, D8): the non-dry delivery test asserts a same-branch
push, no `pr create`, the `Revised:` row, and an unchanged task lifecycle. D8
stated the `IMPLEMENTER_PODMAN_BIN` seam "from the implementer-ponytail task
(PR #2)" should be reused, and that if that PR had not merged we should add the
seam ourselves rather than block. In this worktree the ponytail PR #2 seam is
not present — `bin/implementer-run.sh` invoked `podman` directly with no
call-time seam.

### Problem

Two gaps surfaced while building revise mode:

1. `run_container()`/`stop_container()` in `implementer-run.sh` called `podman`
   directly, so a fixture could not substitute a mock container runtime to
   execute the driver's `main` end-to-end. `review-run.sh` already had this
   solved via a `podman_call()` function seam; the implementer driver did not.
2. The revision archive number must be stable across the two consumers that
   need it (`archive_revision()` writes `revision-<n>-report.md`; the PR-comment
   body in `deliver_revision()` reads it back). If each recomputed `<n>` by
   counting existing `revision-*.md` files, the archive step would bump the
   count and `deliver_revision()` would target the wrong file (n vs n+1).

### Alternatives

- **Depend on the merged PR #2 seam and block otherwise.** Rejected — D8
  explicitly permits adding the seam in-task rather than blocking, and the
  revision tests need it regardless of merge ordering.
- **Keep direct `podman` calls and only test the dry-run path.** Rejected — the
  non-dry delivery story (US3/US5b) is exactly the path that must be proven
  (same-branch push, no new PR, Revised row), so it cannot be left untested.
- **Recompute the revision number at each call site.** Rejected — racy; the
  archive write changes the count observed by delivery.

### Decision

- Add a `podman_call()` seam (`${IMPLEMENTER_PODMAN_BIN:-podman}`) to
  `bin/implementer-run.sh`, mirroring `review-run.sh`, and route
  `run_container()`/`stop_container()` through it (dropping the `exec` prefix
  for the subshell-invoked function seam, exactly as the reviewer driver does).
- Add `gh_call()` (`${IMPLEMENTER_GH_BIN:-gh}`) for the host-side `gh pr
  view`/`pr comment` calls in revise mode.
- Add test seams `IMPLEMENTER_RUNS_ROOT`, `IMPLEMENTER_ARCHIVES_ROOT` (mirroring
  `REVIEWER_RUNS_ROOT`/`REVIEWER_REVIEWS_ROOT`) so fixtures can run offline
  without touching real `$HOME/.factory`.
- Compute `REVISION_N` **once** in `prepare_revision_dir()` (stable across
  archive + delivery), instead of re-counting at each call site.

### Rationale

Mirrors the proven reviewer-driver pattern exactly (decision 04 in session
`019ff79e-181d-7e8b-a869-398b6417d28a`), keeps the driver testable offline, and
eliminates a real off-by-one bug in the revision-report numbering. D8's
"implement after PR #2 merges; else add the seam" fork is resolved by adding the
seam — no blocking.

### Consequences

- `bin/implementer-run.sh` gains `podman_call`/`gh_call` and the three test
  seams; existing (non-revise) behaviour is unchanged because the seams default
  to the real binaries.
- The implementer-driver suite grows revise-mode coverage (Test 14–16):
  dry-run smoke (reconstruct + `--continue`), negatives (merged PR /
  unresolvable slug / missing review → exit 2), and non-dry delivery
  (same-branch push, no `pr create`, `Revised:` row, task stays in-review,
  `revision-1-report.md` archived).
- A follow-up may reconcile whether the ponytail PR #2 adds a duplicate seam
  when it merges (the current in-task seam is a superset and already used).

### Revision triggers

- If `bin/review-run.sh` changes the `podman_call`/seam shape, mirror the change
  here to keep both drivers consistent.
- If the task lifecycle begins tracking revisions as their own rows (e.g.
  `eval-pipeline.py` reading `revision-*`), revisit the `Revised:` row schema
  and the revision-numbering scheme.
