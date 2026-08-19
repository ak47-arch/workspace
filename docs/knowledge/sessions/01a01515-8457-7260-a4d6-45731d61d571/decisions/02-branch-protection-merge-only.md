## Decision: Enforce merge-only on every default branch — GitHub branch protection, no direct pushes

**Status**: accepted
**Date**: 2026-08-18 19:59
**Task**: branch-protection-merge-only
**Project**: software-factory
**Session**: sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl
**Summary**: Enforce merge-only on every default branch (incl. workspace root) via GitHub branch protection (no direct pushes); `bin/merge-pr.sh` is the single operator merge gate.

### Context

Nothing today structurally prevents a direct push to a default branch. The
workspace root's master already received one: `bdac29e` swept unreviewed code
onto master via the CI sync step (decision 09). App repos are PR-only *in
practice* (the implementer pushes branches, merges go through `gh pr merge`)
but nothing enforces it — a misconfigured driver or a stray script could push
master at any time, and only process discipline would catch it. The multi-repo
refactor (`01-multi-repo-delivery-pr-shapes.md`) removes the last legitimate
direct pushes (sync step + `merge-pr.sh`), after which enforcement is safe
everywhere.

### Problem

"Code reaches master only via a merged PR" is currently an invariant enforced
by *where the code lives*, not by the remote. Decision 09 deferred remote-side
enforcement ("branch protection can't distinguish docs from code") — but the
requirement is now deliberately all-encompassing: **no content of any kind is
pushed directly to a default branch; everything merges via a PR.** The remote
must reject direct pushes, and the factory's own tooling must not be exempt.

### Alternatives

- **Legacy branch protection API**: rejected — deprecated by GitHub; rulesets
  are the current API with the same semantics plus future-proofing.
- **Org-level rulesets**: rejected for now — repos span personal-account
  ownership and org policies add admin overhead; per-repo rulesets with one
  shared script are simpler and cover the inventory.
- **Enforce everything immediately, workspace included**: rejected — the
  current headless loop's sync step and `merge-pr.sh` still push master
  directly; protection would break the loop mid-flight. Workspace enforcement
  is sequenced after `multi-repo-delivery-bookkeeping-prs` removes those
  pushes.
- **Required approving reviews > 0**: rejected — the user's merge at UAT *is*
  the review; requiring GitHub approvals adds ceremony with no new authority.

### Decision

Enable **repository rulesets** on the default branch of every first-party repo
(`ak47-arch/workspace`, `goal-agent`, `llamacpp_inference_server`,
`feed_analyser`, `headroom-pi`, `workspace-portability`, `resume`,
`timesheetViewer`, `emotional_architecture` — the same inventory the factory
drivers use, via `config/implementer.json` repo_map + the remote-name map in
`factory.yml`):

- `require_pull_request` (with `required_approving_review_count = 0` — the
  user's merge is the review)
- `block_force_push`, `block_deletions`
- enforcement `active`, **no bypass actors** — the factory PAT and repo
  admins are included in enforcement, so nothing can push around it

Delivery: `bin/enable-branch-protection.sh` (idempotent, `--dry-run`,
`--scope app|workspace|all`) + `bin/test-branch-protection.sh` (verification).
Sequencing: **app repos now** (nothing legitimately pushes their master
today); **workspace root only after `multi-repo-delivery-bookkeeping-prs` is
complete** — the script checks that task's status and refuses workspace scope
otherwise (`--force` exists for operators who accept the breakage).

### Rationale

Enforcement belongs at the remote, not in a script's discipline: once the
ruleset is active, a direct push fails loudly and immediately, and the only
paths into master are PR merges. Sequencing protects the live headless loop
from breaking mid-flight, and the app-repos-first step closes the bdac29e
class of hole on every repo except the workspace (whose last direct-push paths
the multi-repo refactor removes).

### Consequences

- The CI sync step's `git push origin master` fails once workspace protection
  is active — this is the forcing function that guarantees the sync step is
  gone before enforcement lands.
- `merge-pr.sh` cannot push master anymore; its Merge-row bookkeeping must
  flow through the evidence stream (next run's bookkeeping PR / root PR).
- Any future accidental direct push (a misconfigured driver, a stray script)
  is rejected by GitHub with a clear error — fail-fast at the remote.
- Verification of a negative case (push rejected) needs a non-admin token and
  is documented as a one-time manual step per repo; the ruleset GET assertion
  is scripted and CI-runnable.

### Execution (2026-08-18 — executed in-session, not via the loop)

One-time action — the plan's scripts (`bin/enable-branch-protection.sh`,
`bin/test-branch-protection.sh`) were **dropped as over-engineering** (YAGNI:
remote enforcement needs no committed tooling; this decision record + the PRD
execution note are the audit trail).

**Applied + verified via GET on 2026-08-18** (classic branch protection, since
repository rulesets are Pro-gated on private repos):

- `ak47-arch/llamacpp_inference_server` (master)
- `ak47-arch/headroom-pi` (main)
- `ak47-arch/timesheetViewer` (main)

Payload: `required_pull_request_reviews` (0 approvals — the user's merge at
UAT is the review), `enforce_admins: true` (no bypass, incl. the factory
PAT), `allow_force_pushes: false`, `allow_deletions: false`.

**Blocked — GitHub free plan:** private repos (`goal-agent`, `feed_analyser`,
`workspace-portability`, `resume`, `emotional_architecture`) reject BOTH
repository rulesets and the classic branch-protection API with
"Upgrade to GitHub Pro or make this repository public" (HTTP 403). There is
no remote enforcement on free private repos. Open decision: upgrade to Pro,
or accept the gap under a documented policy until then.

**Sequenced:** the `workspace` repo is **public** → protectable on free; it
becomes merge-only as the capstone of `multi-repo-delivery-bookkeeping-prs`
(its sync step and `merge-pr.sh` master pushes must be retired first).

**Negative test (observed 2026-08-18):** `git push origin master` from a
throwaway clone of `ak47-arch/llamacpp_inference_server` using owner
credentials was rejected server-side — `enforce_admins: true` confirmed live:

```
remote: error: GH006: Protected branch update failed for refs/heads/master.
remote: - Changes must be made through a pull request.
! [remote rejected] master -> master (protected branch hook declined)
```

**Task disposition:** `branch-protection-merge-only` is **uncompletable as
written** on the free plan — kept **open** by policy (nothing is closed
directly; it stays `in-prd` with PRD Draft so the loop never picks it up).
Re-evaluate if Pro is adopted.

### Revision triggers

- GitHub deprecates or changes repository rulesets semantics (migrate).
- The factory adopts self-hosted runners or org-level policies that supersede
  per-repo rulesets.
- A legitimate workflow needs to push the default branch directly (should not
  happen by design — investigate instead of adding a bypass actor).
