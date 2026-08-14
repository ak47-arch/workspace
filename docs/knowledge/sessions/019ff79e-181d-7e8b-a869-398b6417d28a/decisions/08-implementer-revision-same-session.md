## Decision: Review-feedback fixes are made by the implementer, resuming its original session

**Status**: accepted
**Date**: 2026-08-14 22:13
**Task**: implementer-revision-mode
**Project**: software-factory
**Session**: sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl

### Context

The first live dogfood cycle (implementer-ponytail, PR #2) produced a
REQUEST_CHANGES review. The question "who fixes it?" surfaced a gap: the
reviewer is read-only by design (decision 03) and never merges (decision 05/07),
but the factory has no automated revision stage — `implementer-run.sh` raises a
fresh PR per task and has no "address review feedback on the open PR" mode.
Historically, fixes were applied operator-side on the PR branch (code-review-agent
PR #1 fix commit 56d7c29).

### Problem

Review findings need a mutating actor. Two sub-decisions: (a) *who* fixes — the
implementer owns the code and the branch, but a fresh implementer run would
either create a second PR or re-derive the implementation cold; (b) *how* —
whether to resume the original implementation session (preserving its context)
or start a new session against the diff + report.

### Alternatives

- **Operator/host applies the fix on the PR branch (status quo).** Rejected as
  the long-term answer — it makes the host the de-facto author of the
  implementer's code and doesn't scale; the implementer's own decisions get
  contradicted by outside edits.
- **Implementer fixes in a fresh session.** Rejected — loses the session's live
  mental model of what it built (layout, decisions, intent). A cold start risks
  misreading its own work, re-deriving the same errors (the committed
  `opensource` symlink contradicts the implementer's own decision record — a
  fresh session has no live memory of that reasoning), and re-committing
  out-of-scope artifacts.
- **Implementer resumes the same implementation session (chosen).** Same
  `--session-id` + `--continue` + same branch/worktree (the mechanism pi already
  uses for container respawn), with the reviewer report injected as the binding
  fix spec.

### Decision

Review findings are fixed by the **implementer**, resumed in the **same
implementation session** (same `--session-id`, `--continue`, same branch), with
the reviewer's `report.md` + review-emerged decision injected as a
**higher-priority authority** than the session's own prior reasoning. New
`implementer-run.sh --revise <pr>` mode reconstructs the run dir + session-dir,
remounts the original worktree, injects the review report, and amends the same
branch. Merge remains operator-gated (decision 07) and the reviewer remains
read-only (decision 03).

### Rationale

Same-session fixes preserve the implementer's mental model of what it built —
the correct file map, its binding rules, and its own decision records stay live
and self-consistent (fixing the exact class of "decision record contradicts
commit" defect seen in PR #2). Single-lineage bookkeeping keeps the task's
Sessions/Decisions trail and the evaluation join (decision 06) coherent. The
mitigated risk is confirmation bias: the author reading the critique may
rationalize findings away, so the review report is deliberately coded as
outranking prior reasoning — findings win where they conflict.

### Consequences

- New `--revise <pr>` mode in `bin/implementer-run.sh`; a Medium task
  (`implementer-revision-mode`) is filed. PR #2 becomes its first real test.
- Run-dir/session-dir reconstruction becomes a tested seam; `--resume` semantics
  get defined for the revision case.
- Until `--revise` ships, fixes are still operator-applied (code-review-agent
  precedent) — an interim, documented fallback, not the target.
- Master push remains merge-gated (decision 07): artifacts accumulate locally
  until the operator merges or explicitly pushes.

### Revision triggers

- If session replay via `--continue` does not reproduce usable context (weak
  recall), drop same-session and fall back to a fresh session driven by the
  report + diff as the full spec.
- If the model cannot defer to the injected report even when it contradicts
  prior reasoning (confirmation bias unmitigated in practice), add a stronger
  mechanism (e.g. report-only directive, no prior-reasoning preamble).
- If a second mutating actor (operator bot) gains fix capability, reconcile with
  the authority model.
