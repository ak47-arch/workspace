## Decision: PR dependency invariant — no undeclared ride-along commits

**Status**: accepted
**Date**: 2026-08-19 05:20
**Task**: [multi-repo-delivery-bookkeeping-prs](../../../../tasks/multi-repo-delivery-bookkeeping-prs.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: bin/merge-pr.sh enforces the invariant for every PR set it merges: 1.

### Context

A docs/knowledge branch was created on top of an open code PR (branch stacking). Merging the docs PR silently carried the code PR's unmerged commits into master; GitHub then auto-marked the code PR MERGED (head commit became reachable). The code was tested and correct, but the merge happened without the explicit review/UAT go-ahead that the code PR was awaiting — invisible, unrecorded intent.

### Problem

With humans in the loop the ride-along was benign. With **automatic pushing and merging**, ambiguity about *which PR owns a commit* is unsafe: an unapproved PR's work could slip to master through an unrelated merge, or two PRs could fight over the same commit. The factory's fail-loud principle requires the ambiguity to be impossible, not noticed.

### Alternatives

- **"Always branch from master" habit** — rejected: habits are not machine-checkable; automation can't enforce intent.
- **Guardrail at branch-creation** — rejected: creation-time is the wrong enforcement point (nothing to verify yet); also blocks legitimate stacked-PR workflows.
- **Merge-time dependency invariant (chosen)**: a PR may bring another open PR's unmerged commits ONLY if it declares `**Depends on:** #N`; undeclared ride-alongs fail loudly; declared deps are validated to be in the merge set and merge FIRST.

### Decision

`bin/merge-pr.sh` enforces the invariant for every PR set it merges:
1. **Declared base**: parse `**Depends on:** #N` from each PR body.
2. **Dangling-dep rejection**: a declared dep outside the set → exit 1.
3. **Ride-along rejection**: for each PR pair, if one head is an ancestor superset of the other (stacked branch) and no declaration exists → exit 1 naming both PRs and the fix.
4. **Dependency-first ordering**: declared base PRs merge before dependents.
5. Backward compatible with minimal gh mocks (`{}` → ancestry check skipped; declared-deps still enforced).

### Rationale
The invariant makes every ride-along either **declared** (allowed, ordered) or **foreign** (rejected) — exactly the property automated merging needs. It tolerates stacking as a deliberate tool (the incident's topology was itself a legitimate dependency: the knowledge doc referenced the session-filter code) while making accidental over-merges impossible. Enforced with ~40 lines of git/gh checking + a 5-case unit suite.

### Consequences
- Merging a docs PR can no longer silently carry an open code PR.
- Stacked PRs require an explicit `**Depends on:**` line; the base merges first.
- `bin/merge-pr.sh` gains the ancestry check (guarded on resolvable heads) and topo ordering.
- Enforcement point is merge-time, so any future auto-merger inherits it.

### Revision triggers
- If GitHub-native stacking/dependency semantics (e.g. draft-PR dependency) replace manual `**Depends on:**` bodies.
- If the ride-along check produces false positives on legitimate shared-base workflows (would relax to declared-base-only).
