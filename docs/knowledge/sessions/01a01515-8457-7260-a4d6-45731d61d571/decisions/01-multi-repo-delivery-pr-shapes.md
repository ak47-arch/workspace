## Decision: Multi-repo delivery — per-repo implementation PRs + PR-based bookkeeping on the workspace root

**Status**: proposed
**Date**: 2026-08-18 19:59
**Task**: multi-repo-delivery-bookkeeping-prs
**Project**: software-factory
**Session**: sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl

### Context

The factory's two-stream model delivers code via PRs (app repos) but pushes
bookkeeping (archives, sessions, transitions, PR tracking) directly to the
workspace root's master: the CI workflow's "Sync tracking commits to master"
step does `git add -A` + `git push origin master` (`if: always()`), and
`bin/merge-pr.sh` pushes master after recording the Merge row. The workspace
repo tracks only the meta-layer (all app dirs are gitignored), so the code
stream and the evidence stream have structurally different homes — and the
evidence stream never had a PR mechanism at all.

The direct-push safety rests on an incidental property — code changes live in
the run-dir worktree clone, never in the runner checkout — and it already
failed once: `bdac29e` swept real code (`bin/implementer-run.sh` + tests) onto
master unreviewed (decision 09, `09-code-master-pr-gate.md`). Master's history
mixes reviewed code, unreviewed evidence, and (once) unreviewed code; auditing
it required a 388-commit classification script.

### Problem

Requirement set: (1) a task may touch **multiple** application repos and must
raise one implementation PR **per repo**; (2) bookkeeping merges **only** to
the workspace root; (3) a normal task raises **at least two PRs** — one or
more implementation PRs plus one bookkeeping PR on the root; (4) the converse —
when code lands on the root itself, one PR carries **both** implementation and
bookkeeping; (5) both scenarios must be handled robustly with fail-fast /
fail-loud monitoring. Today only single-repo exists, and the bookkeeping
stream bypasses PRs entirely.

### Alternatives

- **Keep the sync step, harden it** (`git add docs/` + tripwire): rejected as
  the end-state — still direct pushes to master, still no PR for evidence, and
  it keeps the two streams asymmetric. Accepted only as an interim stopgap.
- **Monorepo collapse** (un-ignore app dirs, one repo, one PR per run carrying
  code + evidence): rejected — history/remote migration of 7+ repos, collapses
  the control-plane/product-code separation, and breaks independent
  deployment/visibility. Flagged as over-engineering for a working factory.
- **Auto-merge the bookkeeping PR by the workflow after APPROVE**: deferred —
  preserves autonomy but the bot still writes master (via PR mechanics). The
  user's "everything through the PR" preference and UAT authority favour
  user-merge; kept as an option if autonomy demands it later.
- **N containers, one per repo**: rejected — fragments cross-repo context and
  multiplies respawn/session plumbing; one brain keeps the session and
  revision continuity (decision 08) intact.

### Decision

A task touches a **declared set of repos**; the workspace root is a repo like
any other. Exactly two shapes:

- **Shape A (root not touched):** N implementation PRs (one per app repo,
  base = that repo's manifest branch, label `factory:needs-review`) + 1
  **bookkeeping PR** on the root (docs-only, label `factory:bookkeeping`) →
  **N+1 PRs**.
- **Shape B (root touched):** N−1 app PRs + 1 root PR carrying **code and
  bookkeeping as separate commits** on the same branch → **N PRs**.

Collapse rule: **bookkeeping rides the root code PR iff the root is in the
touched set; otherwise bookkeeping is its own PR.** The invariant asserted
after every delivery: `(root code PR exists AND no bookkeeping PR) XOR (no
root code PR AND exactly one bookkeeping PR)`.

Supporting decisions:

- Repo declaration lives in the PRD header as `**Repos**:` (comma-separated
  `repo_map` values; `.`/`workspace` = root). Absent → single repo derived from
  the task's `**Project**:` (backward compatible). **The declaration is the
  sandbox**: only declared repos get worktrees, so touching an undeclared repo
  is structurally impossible.
- **One brain, N worktrees**: one container, one session; worktrees under
  `RUN_DIR/worktrees/<repo-key>/` (the existing single-worktree pattern, made
  plural).
- Bookkeeping PR is raised by `factory-run.sh` at **loop end, success or
  failure** (so evidence always persists), merged by the **user at UAT** —
  never auto-merged, never direct-pushed.
- Bookkeeping PR diff must touch **only `docs/`** — a deterministic tripwire
  at raise time (the decision-09 hardening made structural via PR diff instead
  of `git add -A`).
- **Per-repo revision**: on REQUEST_CHANGES, only the repos whose PRs were
  rejected are revised (same branches, same original session — decision 08);
  the revision cap is per task.
- Loop state reads move **off the checkout**: verdicts + review reports read
  from the run dir; the pickup gate checks for an open `[factory] <slug>` PR
  via `gh` per declared repo, so master lag can never cause re-implementation.
- Branch naming: `factory/<slug>/<repo-key>/<ts>`; bookkeeping:
  `factory/<slug>/bookkeeping/<ts>`.
- Retire: the CI sync step's `git add -A` + `git push origin master`; and
  `merge-pr.sh`'s master push (Merge rows land via the evidence flow).
- Monitoring backbone: a **run manifest** (JSON) — per-repo
  `{branch, pr, verdict, state}`, `bookkeeping_pr`, `revisions`, `outcome` —
  written every run, printed at the end, bundled into the factory-traces
  bundle, and mirrored into the bookkeeping PR body. Fail-loud = non-zero
  exit + manifest surfaced.

### Rationale

The PR is the only reviewed, user-gated artifact (decision 05); routing
evidence through PRs makes master "everything merged via PR" instead of "code
reviewed + evidence synced", and makes the bdac29e class of failure
structurally impossible. The collapse rule keeps the root case to one PR
instead of forcing a redundant split. One brain preserves cross-repo coherence
and the session-continuity machinery that already works. User-merge of the
bookkeeping PR preserves the authority split with zero bot writes to master.

### Consequences

- Every run produces ≥1 PR; UAT is "merge the PR set" (N code + 1 bookkeeping,
  or 1 root PR). `bin/merge-pr.sh` becomes multi-PR with an all-open pre-flight
  and per-PR Merge rows; the task completes only when the whole set is merged.
- Review archives land in the run dir during the run and reach the repo only
  via the bookkeeping PR at loop end — the revise leg and verdict read-back
  must switch to run-dir paths.
- The "tracking commits accumulate locally and ride up with the merge" model
  (decision 07 local path) dies: bookkeeping is PR-based everywhere, locally
  and in CI.
- Master becomes "everything merged via PR" — no unreviewed content of any
  kind, by construction.
- Implementation cost is spread across drivers, loop, workflow, merge tool,
  and tests — this is a Large task and the factory's own gate applies.

### Revision triggers

- A run whose bookkeeping PR diff touches a code path (tripwire fires) — the
  invariant is broken, re-audit.
- The loop's autonomy breaks because evidence now waits for UAT merge (if
  pickup cadence suffers, revisit workflow-auto-merge of the bookkeeping PR).
- A task genuinely needs a repo the agent only discovers mid-run (the
  declaration-as-sandbox model fails) — consider a mid-run "declare repo X"
  escalation path.
