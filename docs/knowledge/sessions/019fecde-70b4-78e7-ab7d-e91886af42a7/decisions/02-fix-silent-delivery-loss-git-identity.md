## Decision: Fix silent delivery loss — configure git identity in the run-dir clone before the host commit

**Status**: accepted
**Date**: 2026-08-12 03:40
**Task**: [implementer-agent](../../../../tasks/implementer-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: 1.

### Context

The first fully-successful live run of the implementer harness
(`extension-inline-agent` on feed_analyser) appeared to "fail" as a no-op: the
pushed branch came out *identical* to `public-release`, GitHub refused to raise
a PR ("No commits between…"), and the run was initially misread as
"already-implemented / nothing to do."

The implementer had in fact written the entire feature (23 files, ~+3600 lines:
`capture/agent-service/`, Ask panel, `agent-client.js`, `server/index.py`,
`bin/rebuild-index.py`, tests) into the run-dir worktree. That work was never
committed, so the branch was pushed as just the unmodified base.

### Problem

The driver's "host authors the single commit" step ran:

```bash
git -C "$WORKTREE" add -A
git -C "$WORKTREE" diff --cached --quiet \
  || git -C "$WORKTREE" commit -q -m "implementer(...)"
```

The run-dir clone of a third-party repo is a **fresh clone with no
`user.name`/`user.email`**, so `git commit` failed with
`fatal: unable to auto-detect email address (Author identity unknown)` and
returned non-zero. The driver **ignored that failure** (no `||` abort on the
commit itself; the following "Host-authored worktree commit" line still printed,
and the push proceeded), so the implementer's deliverable silently never entered
the branch. Result: an identical-to-base branch, no PR, and the appearance of a
no-op task.

This is a silent-failure bug in the delivery path — the worst kind, because it
masquerades as "nothing to do" and can delete the evidence (the branch) and
mislead diagnosis.

### Alternatives

- **Blame the caller / require identity globally.** Fragile; the whole point is
  the harness must run on any repo and any CI identity.
- **Catch + report the commit failure.** Needed but insufficient alone — the
  deliverable still wouldn't be committed.
- **Configure driver identity in the clone (chosen).** Set local
  `user.name`/`user.email` in the worktree clone at prepare time, and pass `-c`
  identity on the commit as belt-and-suspenders, with explicit no-op/error
  handling so a commit that should exist but doesn't is surfaced loudly.

### Decision

1. In `prepare_run_dir`, immediately after cloning, set local config in the
   run-dir clone:
   ```bash
   git -C "$WORKTREE" config user.name  "${IMPL_GIT_NAME:-factory}"
   git -C "$WORKTREE" config user.email "${IMPL_GIT_EMAIL:-factory@ak47.local}"
   ```
   (overridable via env for callers that want a real identity).
2. In `push_and_pr`, commit with `-c user.name/… -c user.email/…` and treat a
   failed commit (when there ARE staged changes) as a hard error (`return 2`),
   and emit an explicit `[no-op]` message when there is genuinely nothing to
   commit.

### Rationale

The host is the sole git actor, so it must supply the identity — it cannot
assume a third-party clone carries one. Configuring it once at prepare time is
cheap and removes a whole class of silent subcommand failures. Failing loudly on
an expected-but-missing commit converts a silent data-loss bug into a
detectable, actionable error.

### Consequences

- The host-authored commit now reliably lands, so the implementer's work enters
  the pushed branch and a PR can be created.
- A genuinely-empty run produces an explicit "no-op" message instead of a
  silently-identical branch.
- Identity is configurable via `IMPL_GIT_NAME` / `IMPL_GIT_EMAIL` (default
  `factory` / `factory@ak47.local`).
- Recovered the immediate lost work by committing the staged run-dir worktree
  and raising `ak47-arch/feed_analyser#1`.

### Revision triggers

- If the harness runs under a CI that injects a global identity, the local
  config is redundant but harmless.
- If a future run shows a worktree commit "succeeded" but the pushed branch is
  still identical to base, re-open this — it would point to a different cause
  (e.g. the implementer resetting/removing files before exit).
- If identity should reflect the end-user rather than the driver, rework the
  default via `IMPL_GIT_*` env.
