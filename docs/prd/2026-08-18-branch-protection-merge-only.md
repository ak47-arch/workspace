# PRD: Enforce merge-only on all repos — no direct pushes to any default branch

**Date**: 2026-08-18 19:59
**Status**: [Draft](./manifest.json)
**Owner**: software-factory workspace
**Task**: [branch-protection-merge-only](../tasks/branch-protection-merge-only.md)
**Repos**: workspace (root)
**Session**: [session.jsonl](../knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl)
**Decisions**:
  - [02-branch-protection-merge-only](../knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/decisions/02-branch-protection-merge-only.md)
**Context**: decision 09 `09-code-master-pr-gate.md` (the bdac29e direct-sweep) · `docs/reference/implementer-agent.md` (repo inventory) · companion task `multi-repo-delivery-bookkeeping-prs`

## Problem statement

Nothing structurally prevents a direct push to a default branch today. The
workspace repo's master already received unreviewed code once (`bdac29e`,
decision 09); app repos are only PR-only *in practice* (nothing enforces it).
The requirement is deliberate and total: **no content of any kind is pushed
directly to a default branch — everything merges via a PR.** Enforcement must
live at the remote (GitHub branch protection), not in script discipline, and
the factory's own credentials must not be exempt.

## Solution overview

Enable GitHub **repository rulesets** on the default branch of every
first-party repo, via an idempotent script `bin/enable-branch-protection.sh`
(applicable `--scope app|workspace|all`), with:

- `require_pull_request` (required approving review count = 0 — the user's
  merge at UAT is the review, decision 05
  `sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/05-review-never-merges.md`)
- `block_force_push`, `block_deletions`
- enforcement `active`, **no bypass actors** — the FACTORY_GH_PAT and repo
  admins are included in enforcement

Repos: `ak47-arch/workspace`, `goal-agent`, `llamacpp_inference_server`,
`feed_analyser`, `headroom-pi`, `workspace-portability`, `resume`,
`timesheetViewer`, `emotional_architecture` — the same inventory the drivers
use (`config/implementer.json` repo_map + the remote-name map in
`.github/workflows/factory.yml`; path `workspace` = `ak47-arch/workspace`).

Sequencing: **app repos now** (nothing legitimately pushes their master
today); the **workspace root only after `multi-repo-delivery-bookkeeping-prs`
is complete** — the script reads that task's status and refuses workspace
scope otherwise (`--force` for operators who knowingly accept breaking the
current sync step).

## User stories

1. A direct push to the default branch of any first-party app repo is
   rejected by GitHub (ruleset enforced; verified per repo via the ruleset API
   and a documented one-time negative push test with a non-bypass token).
2. PR-based merges still succeed — `gh pr merge` (and `merge-pr.sh`, after the
   companion refactor) completes normally.
3. `bin/enable-branch-protection.sh` is **idempotent** (safe to re-run), has a
   `--dry-run` that reports without changing, and applies the identical
   ruleset to every repo in scope.
4. The script **respects sequencing**: `--scope workspace` exits non-zero with
   a clear message while `multi-repo-delivery-bookkeeping-prs` is unfinished
   (unless `--force`).
5. The ruleset has **no bypass actors** — the factory PAT and admins cannot
   push the default branch directly.

## Implementation decisions

- Use **repository rulesets** (`POST /repos/{owner}/{repo}/rulesets`, target
  the default branch), not the legacy branch-protection API.
- Enforcement `active`; rules `require_pull_request` (approvals 0, `dismiss_
  stale_reviews_on_push`: false), `block_force_push`, `block_deletions`.
- Repo inventory sources: `config/implementer.json` `repo_map` values + the
  `REPO_NAME` mapping already in `factory.yml` (llm→llamacpp_inference_server,
  survival-infrastructure→goal-agent); derive the list once in the script with
  the hardcoded fallback above to stay runnable without jq.
- Sequencing check reads `docs/tasks/multi-repo-delivery-bookkeeping-prs.md`
  `**Status**: complete`.
- `--dry-run` prints the payload and repos without calling the API.

## Testing decisions

- `bin/test-branch-protection.sh` asserts, with a mocked `gh` seam
  (`BP_GH_BIN` pointing at a fixture): dry-run makes no API calls;
  idempotency (two runs produce one ruleset per repo); the sequencing gate
  (workspace scope refused while the companion task is not `complete`); the
  ruleset payload shape (`enforcement: active`, the three rules, no bypass
  actors) for both `app` and `workspace` scopes.
- The script's repo-inventory derivation is unit-tested against the same
  repo_map fixture the driver tests use.
- Post-apply verification is scripted read-only: `gh api
  repos/ak47-arch/<repo>/rulesets` per repo asserting the required rules
  (CI-runnable); the negative push test stays a documented one-time manual
  step (needs a non-bypass token — not available on CI runners).

## Architecture

No architecture change to the factory: the ruleset is a remote-side guard that
makes the sync step's `git push origin master` fail loudly once the workspace
is protected — the forcing function that guarantees the direct-push stream is
retired (companion task) before enforcement lands there.

## Location (file map)

| Change | Path |
|---|---|
| Ruleset applier (idempotent, scoped, sequenced) | `bin/enable-branch-protection.sh` |
| Verification (ruleset assertions) | `bin/test-branch-protection.sh` |
| Docs: enforcement + manual negative-test steps | `docs/factory-context.md` (ops note) |

## Acceptance (verification)

```bash
bash bin/test-branch-protection.sh          # dry-run, idempotency, sequencing gate, payload shape
bash bin/enable-branch-protection.sh --scope app --dry-run
# operator then applies:
bash bin/enable-branch-protection.sh --scope app
```

Plus post-apply verification: `gh api repos/ak47-arch/<repo>/rulesets`
returns the ruleset with `require_pull_request` + `block_force_push` +
`block_deletions` enforced for every repo in scope, and a documented manual
negative test (non-bypass token push to `<repo>'s` default branch is
rejected; a created-and-merged PR succeeds).

## Execution note (2026-08-18 — done in-session, not via the loop)

Executed directly; the planned scripts were **not created** (one-time action —
YAGNI; the decision record `02-branch-protection-merge-only.md` is the audit
trail).

- **Applied + verified via GET:** classic branch protection on
  `ak47-arch/llamacpp_inference_server` (master), `ak47-arch/headroom-pi`
  (main), `ak47-arch/timesheetViewer` (main) — `required_pull_request_reviews`
  (0 approvals), `enforce_admins: true` (no bypass, incl. the PAT),
  `allow_force_pushes: false`, `allow_deletions: false`.
- **Blocked — GitHub free plan:** private repos (`goal-agent`,
  `feed_analyser`, `workspace-portability`, `resume`, `emotional_architecture`)
  reject both rulesets and the classic protection API (HTTP 403, Pro-gated).
  No remote enforcement exists there on free; open decision: Pro upgrade or a
  documented gap.
- **Sequenced:** the `workspace` repo is public → protectable on free; enabled
  as the capstone of `multi-repo-delivery-bookkeeping-prs`.
- This PRD returns to **Draft** so the headless loop does not pick it up while
  the platform constraint is unresolved.

**Disposition:** the task is **uncompletable as written on the free plan** —
kept open (never closed directly). This PRD stays **Draft** permanently until
the platform constraint resolves, so the loop can never pick the task up.
Re-evaluate if GitHub Pro is adopted (then protect the 5 private repos in one
pass); the workspace portion is sequenced into
`multi-repo-delivery-bookkeeping-prs`.

## Out-of-scope

- Legacy branch protection API migration of existing settings.
- Required approving reviews > 0, CI status checks on PRs, merge queues,
  CODEOWNERS.
- Org-level rulesets (workflow spans personal-account repos).
- Locking non-default branches (topical protection only).
- Merging PRs (unchanged: `merge-pr.sh` / `gh pr merge` for the user).