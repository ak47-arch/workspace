## Decision: drop the committed `opensource` symlink from the PR; gitignore matches a bare symlink (REVISED)

**Status**: accepted
**Date**: 2026-08-14 18:45 (revised after review)
**Task**: [implementer-ponytail](../../../../tasks/implementer-ponytail.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Related review**: review/decisions/01-implementer-ponytail.md (5b63c492)
**Summary**: Delete the opensource symlink from the worktree (done).

### Context

The original implementer run intended to make the bare-worktree factory suite
self-contained by symlinking the gitignored host `opensource` dir
(`opensource -> /workspace/opensource`) and copying the gitignored
`workspace-portability/workspace_restore_manifest.json`. The intent was that both
remain **untracked** and never enter the commit.

That intent **failed silently for the symlink**: the `.gitignore` pattern
`opensource/` (directory-only, trailing slash) does **not** match a symlink
(file mode 120000), so the host's `git add -A` committed the `opensource` symlink
into PR #2 (`new file mode 120000`). The earlier version of this decision record
incorrectly asserted the symlink "never enter[s] the commit" — the review (D7)
found it **was** committed. This is a correction of that record, not a reversal
of the original design intent.

### Problem

PR #2 contained an out-of-scope committed artifact:
- absent from the PRD file map (which lists only `config/implementer.json`,
  `bin/implementer-run.sh`, `.pi/agents/implementer.md`,
  `bin/test-implementer-driver.sh` + bookkeeping);
- unused by every code path (all driver/config/test paths use the absolute
  `/workspace/opensource/ponytail/skills` path);
- a dangling absolute-host-path symlink on any non-host clone/CI.

### Alternatives

1. **Keep the symlink committed.** Rejected: out-of-scope, breaks other clones,
   contradicts the PRD file map and the "no vendoring / live checkout, read-only"
   intent (decision D2).
2. **Untrack the symlink but leave the file present.** Requires a git index
   mutation (`git rm --cached`) which the implementer cannot perform (host owns
   git); and a tracked file is unaffected by `.gitignore`, so merely adding a
   gitignore rule would not untrack it.
3. **Delete the symlink from the worktree** so the host-authored commit records
   its removal, and correct `.gitignore` to match a bare symlink so it can never
   re-enter a commit. Chosen.

### Decision

- Delete the `opensource` symlink from the worktree (done). The host's next
  commit removes it from the PR tree, leaving only the four PRD-mapped source
  files plus the `.gitignore` scope-correction.
- Replace the `.gitignore` directory-only `opensource/` pattern with `opensource`
  (no trailing slash) so a bare `opensource` symlink/file is ignored, matching
  both the directory and a symlink.
- Keep the gitignored untracked `workspace-portability/workspace_restore_manifest.json`
  as a legitimate env bootstrap (already covered by `/workspace-portability/`,
  line 22); it is not committed and was never part of any finding.

### Rationale

- The review is the binding authority: fix exactly the committed-symlink scope.
- Deletion is the only implementer-safe way to guarantee the symlink leaves the
  tree given the no-git constraint (a gitignore rule alone cannot untrack an
  already-tracked file).
- Correcting `.gitignore` preserves the original untracked-bootstrap intent for
  any future worktree without re-introducing a committed artifact.

### Consequences

- Clean, PRD-scoped diff: four source files + `.gitignore` correction, no
  broken absolute-path artifact.
- `test-review-driver` Test 7 (`opensource/ponytail/skills/...` at checkout root)
  now requires a live `opensource` at the checkout on a real host; in a bare
  clone it is 60/61. The review's binding decision 01 explicitly accepts this
  ("still requires a live `opensource` at the checkout on a real host"). On the
  deliverer's real host it is 61/61.
- `test-implementer-driver` is 33/34 on a bare clone (gitignored manifest
  absent) and 34/34 with it present — pre-existing environmental, fails at base.

### Revision triggers

- If any code path begins resolving skills via the repo-root `opensource`
  relative path, revisit (contradicts the absolute-path precedent in
  `review-run.sh` / decision 04).
- If `.gitignore` is changed to stop excluding `/workspace-portability/` or the
  `opensource` bootstrap, the untracked artifacts would re-enter commits.
