## Decision: Review worker is read-only — may run read-only git, never gh

**Status**: accepted
**Date**: 2026-08-13 23:00
**Task**: [code-review-agent](../../../../tasks/code-review-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The review worker MAY run read-only git subcommands (diff, log, show, status) against its PR-head checkout; it must never mutate anything (no add/ commit/push/checkout/wo

### Context

Defining the git/compliance contract for the code-review worker. The implementer's
rule is absolute: **no git commands at all** — the host owns every mutation and the
container is a pure writer-side worker. The reviewer's job is the mirror image:
read the PR head and reason about it, so it cannot do its job without reading git
history/diffs.

### Problem

Copying the implementer's "never any git command" rule verbatim would force the
driver to precompute and pass every diff/snippet, bloating the brief and losing
context. But the reviewer must still be compliance-safe: it must not mutate the
repo, and it must never hold GitHub credentials.

### Alternatives

- **Absolute no-git (implementer rule)** — safe but unworkable: the worker needs
  `git diff base...head`, `git log`, `git show` to review properly. Rejected for the
  reviewer, kept for the implementer.
- **Full git + gh in container** — power-creep; a compromised worker could push.
  Rejected: no token is mounted, and mutation is meaningless on a read-only checkout.
- **Read-only git, no gh (chosen)** — explicit permission for `diff/log/show/status`
  (read-only subcommands), prohibition on anything mutating, and `gh` is
  impossible-by-construction (no token in container). All mutations, PR comments,
  labels, and lifecycle transitions stay driver-side.

### Decision

The review worker MAY run read-only git subcommands (`diff`, `log`, `show`,
`status`) against its PR-head checkout; it must never mutate anything (no add/
commit/push/checkout/worktree ops) and must never run `gh`. The brief's rules
section + the read-only persona enforce this; the driver test suite asserts the
worktree is clean and no token env reaches the container.

### Rationale

This is a deliberate, documented divergence from the implementer's git rule, driven
by the role difference: implementer = writes (host owns git for a reason), reviewer
= reads (its product is judgment, so it needs the history). Keeping mutations on
the host preserves the single-git-actor invariant where it matters.

### Consequences

- The reviewer can self-serve diffs and commit history — no driver precomputation.
- Two git policies now exist (implementer: none; reviewer: read-only); the
  personas and skills must state each explicitly to avoid drift.
- Reviewer compliance surface = "read-only subcommands only"; driver test asserts
  clean worktree post-run.

### Revision triggers

- A reviewer is ever allowed write access (e.g. auto-fix commits) → this decision.
- The container gains a GitHub token for any reason → this decision + the
  implementer's no-token invariant.
