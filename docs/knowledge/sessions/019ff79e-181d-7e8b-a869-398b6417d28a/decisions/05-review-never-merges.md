## Decision: The code-review agent never merges PRs — merge stays a human-gated operator step

**Status**: accepted
**Date**: 2026-08-14
**Task**: [code-review-agent](../../../../tasks/code-review-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The code-review agent never merges and never auto-completes a task.

### Context

First dogfood of the review agent: PR #1 was reviewed (APPROVE), but the operator
then asked — "we don't want the review agent to be merging PRs do we?" — re-examining
the final step of the assembly line. The pipeline already enforces a strict
authority split: `prd-reviewer` gates plans, the `implementer` builds, the
`code-reviewer` checks, and **UAT + go-ahead stays with the user**. The review
driver has no merge path today (US6), but this was implied, never a recorded rule.

### Problem

If the reviewer (or its driver) merged on APPROVE, it becomes judge **and**
executor. Merge is the final authority gate; UAT sign-off — running the product,
judging UX, accepting risk — is exactly what an agent cannot do. Auto-merge would
silently convert the reviewer into the release authority, making the user's
go-ahead decorative, and would collapse the check/authority separation the whole
pipeline is built on.

### Decision

The code-review agent **never merges and never auto-completes a task**. Merge is a
distinct, explicit, human-gated step: user UAT → go-ahead → **operator** merges
(even a CLI/automation later runs as the operator role, never as the reviewer).
The driver's deliver phase stops at: report → PR comment → outcome label →
transition `in-progress → in-review`. The merged driver carries an explicit
`AUTHORITY SPLIT` comment in its deliver block (fix commit 56d7c29) so no future
editor re-introduces a merge path by accident.

### Rationale

Roles stay single-purpose; checks stay non-authoritative; the user retains the
final decision. Automation matures the *checks* (already versioned skills) and the
*recording* (decisions 06 task-PR tracking), not the *authority*.

### Consequences

- Operator merged PR #1 (`f7f672f`) on the user's go-ahead — the reviewer never
  touched the merge.
- A future "release manager" would be a separate authority with its own mandate,
  not the reviewer.
- Guardrail: review suites + any future automation should assert the driver has no
  merge path (mirror of the no-gh-token guardrail).

### Revision triggers

- The user explicitly designates an automated merger with its own mandate.
- A separate release-manager agent is created (different authority, different rules).
