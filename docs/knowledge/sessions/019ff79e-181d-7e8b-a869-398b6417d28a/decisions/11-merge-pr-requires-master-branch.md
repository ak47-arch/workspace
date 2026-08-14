## Decision: `merge-pr.sh` operates on the checked-out branch — operator must run it on master

**Status**: accepted
**Date**: 2026-08-15 01:12
**Task**: software-factory
**Project**: software-factory
**Session**: sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl

### Context

Merging PR #2 required an operator rebase of the feature branch onto master
(PR #3 had moved master; one conflict in `bin/implementer-run.sh`). The rebase
was done on a temporary local branch `_rebase-ponytail`, force-pushed, then —
in the same command — `bin/merge-pr.sh 2` was invoked **while still checked
out on `_rebase-ponytail`**.

### Problem

`merge-pr.sh` appends the decision-06 `Merge:` row via
`( cd "$WORKSPACE" && git add docs/tasks/<slug>.md && git commit )` — the
commit lands on **whatever branch is checked out**, not necessarily master.
The Merge-row commit was created on `_rebase-ponytail` (parent = rebased branch
head), and deleting that branch orphaned the row. The merge itself succeeded on
origin (`c469390`), but the row vanished from the tree and had to be recovered
via reflog forensics and re-landed on master (`24e614d`).

### Alternatives

- **Guard in the tool**: `merge-pr.sh` exits 2 unless `git branch --show-current`
  is `master`. Chosen — one-line, makes the invariant explicit instead of
  relying on operator discipline.
- **Operate on the master ref regardless of checkout** (e.g. `git checkout
  master` internally or `git -C "$WORKSPACE" commit` on a detached master).
  Rejected — mutating the worktree branch state inside the tool is surprising
  and interacts badly with concurrent driver runs on the same workspace.
- **Rely on the operator to remember.** Rejected — this session is the proof it
  fails.

### Decision

`merge-pr.sh` must run with the workspace's current branch = `master`. The tool
gains a guard at startup: if `git -C "$WORKSPACE" branch --show-current` is not
`master`, exit 2 with a message naming the offending branch. The operator flow
becomes: rebase on a temp branch → force-push → **checkout master** → merge.

### Rationale

The tool's contract is "operator merge authority, decision 07" — it should fail
loudly when its precondition (on master, where task tracking commits belong) is
not met, rather than silently committing tracking data to a feature branch that
may be deleted.

### Consequences

- The orphaned-Merge-row failure mode is impossible going forward.
- Operators doing rebase-then-merge flows must `git checkout master` before
  invoking the tool (the guard will tell them if they forget).
- A test case (merge on a non-master branch → exit 2) should be added to
  `bin/test-merge-pr.sh`.

### Revision triggers

- If the factory ever supports merging from a detached/CI context, re-examine
  where tracking commits belong.
- If the tool's guard test is not added to `test-merge-pr.sh`, treat this
  decision as only partially implemented.