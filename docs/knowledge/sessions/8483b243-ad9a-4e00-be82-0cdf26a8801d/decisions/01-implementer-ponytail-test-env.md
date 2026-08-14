## Decision: gitignored-environment bootstrap for the factory test suite in a bare worktree

**Status**: accepted
**Date**: 2026-08-14 15:55
**Task**: implementer-ponytail
**Project**: software-factory
**Session**: sessions/8483b243-ad9a-4e00-be82-0cdf26a8801d/session.jsonl

### Context

The factory test sweep (`test-implementer-driver`, `test-review-driver`,
`test-factory-run`, `test-merge-pr`, `test-transition-task`) is expected to stay
green in any worktree clone. Two of the suites' fixtures depend on artifacts
that are **gitignored** and therefore absent from a bare `git clone`:

- `workspace-portability/workspace_restore_manifest.json` — the driver's
  `resolve_repo()` needs it to resolve a project's manifest branch
  (`test-implementer-driver.sh` copies it into the fixture).
- `opensource/ponytail/skills/` — the review suite asserts the live ponytail
  skills dir exists at the driver's checkout (`test-review-driver.sh` Test 7).

In the worktree these do not exist, so two pre-existing assertions fail
(`resolve_repo ... expected public-release`; `ponytail skills dir not found`).

### Problem

How to run the full factory suite green inside `/sandbox/worktree` — which is a
bare clone without these host-generated, gitignored directories — without
modifying the read-only `/workspace` mount and without polluting the commit.

### Alternatives

1. **Do nothing / document as environmental.** Leaves the suite red in any
   worktree clone; fails the PRD's "full suite sweep green" acceptance.
2. **Copy the files into the worktree.** Would work but they are gitignored, so
   the host `git add -A` would silently skip them and the commit would not carry
   them; still only fixes the worktree, and adds non-source artifacts.
3. **Symlink/copy the gitignored host artifacts into the worktree, relying on
   .gitignore to keep them out of the commit.** The host already has both; the
   worktree is a host-mounted dir, so read-only references are safe.

### Decision

Chosen alternative 3. In `/sandbox/worktree`:

- `workspace-portability/workspace_restore_manifest.json` copied from the host
  `/workspace` mount (dir is gitignored via `/workspace-portability/`).
- `opensource/` created as a symlink to `/workspace/opensource` (gitignored via
  `opensource/`), making the live ponytail skills readable from the worktree.

Both are covered by `.gitignore`, so they never enter the host-authored commit;
the commit contains only the four real source files changed by this task.

### Rationale

- Satisfies the PRD's "full suite sweep green" acceptance deterministically.
- Does not touch the read-only `/workspace` mount (no bypass).
- No secrets, no git commands, no remote operations.
- Keeps the delivered diff clean (gitignored env bootstrap never committed).

### Consequences

- The worktree carries host-only, non-committed artifacts (`opensource` symlink,
  `workspace-portability` manifest) that make the suite self-contained. They are
  durable on the host mount but invisible to git.
- On a real host with `jq` + a live `opensource/` checkout these already exist,
  so behavior is identical to production; the sandbox simply mirrors them.
- If a future worktree needs a different `opensource/` location, the symlink
  target must be updated accordingly.

### Revision triggers

- If `.gitignore` ever stops excluding `/workspace-portability/` or
  `opensource/`, the commit would start capturing these artifacts — revisit.
- If a test suite begins requiring a *tracked* copy of either artifact, the
  decision changes (but that would contradict decision 02's "no vendoring" rule
  for ponytail).
