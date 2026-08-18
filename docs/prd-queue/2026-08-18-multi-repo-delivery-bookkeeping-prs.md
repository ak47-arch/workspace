# PRD: Multi-repo delivery — per-repo implementation PRs + PR-based bookkeeping on the workspace root

**Date**: 2026-08-18 19:59
**Status**: Draft
**Owner**: software-factory workspace
**Task**: multi-repo-delivery-bookkeeping-prs
**Repos**: workspace (root)
**Session**: `docs/knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/decisions/01-multi-repo-delivery-pr-shapes.md`
  - `docs/knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/decisions/02-branch-protection-merge-only.md`
**Context**: `docs/factory-context.md` (assembly_line + agents) · `docs/reference/implementer-agent.md` · `docs/reference/reviewer-agent.md` · decision 04/07/08/09 in the harness session `01a00c50-b714-7811-8086-3bc6e0a8ea64`

## Problem statement

The factory's delivery is single-repo and its evidence stream bypasses PRs:

1. **Single-repo only.** A task maps to exactly one repo (`repo_map` in
   `config/implementer.json`). Cross-cutting work spanning two app repos
   cannot be a single task — it must be sharded into per-repo tasks, losing
   end-to-end traceability (a core factory value).
2. **Bookkeeping is pushed directly to master.** The CI workflow's "Sync
   tracking commits to master" step does `git add -A` + `git push origin
   master` (`if: always()`), and `bin/merge-pr.sh` pushes master after
   recording the Merge row. Master therefore receives unmerged, unreviewed
   content — the bdac29e incident (decision 09) already swept real code
   (`bin/implementer-run.sh` + tests) onto master unreviewed, and the safety
   of the design rests on an incidental property (code lives in the run-dir
   worktree clone, never in the runner checkout) rather than any guarantee.
3. **The workspace stream has no PR mechanism.** The workspace repo tracks
   only the meta-layer (all app dirs are gitignored); code PRs live in app
   repos the workspace physically cannot carry. With `branch-protection-merge-
   only` (companion task) enforcing PR-only master, the direct-push streams
   (sync step, merge-pr.sh) must be replaced by PR-based delivery.

## Solution overview

A task touches a **declared set of repos** (PRD header `**Repos**:`, values of
`config/implementer.json` repo_map; `.`/`workspace` = root). The workspace
root is a repo like any other. Exactly two shapes, no third:

- **Shape A (root not touched):** N implementation PRs — one per app repo,
  base = that repo's manifest branch, label `factory:needs-review` — plus 1
  **bookkeeping PR** on the root (`factory:bookkeeping`, **docs-only**) →
  **N+1 PRs**.
- **Shape B (root touched):** N−1 app PRs plus 1 root PR carrying **code and
  bookkeeping as separate commits on the same branch** → **N PRs** (the
  collapsed case).

Collapse rule (the only rule): **bookkeeping rides the root code PR iff the
root is in the touched set; otherwise bookkeeping is its own PR.** Delivery
invariant asserted after every delivery:

```
(root code PR exists AND no bookkeeping PR) XOR (no root code PR AND exactly one bookkeeping PR)
```

Mechanics:

- **The declaration is the sandbox.** Only declared repos get worktrees
  (`RUN_DIR/worktrees/<repo-key>/`), so an undeclared repo is structurally
  untouchable. If a story needs an undeclared repo, the agent flags it in the
  report and the run fails loudly with "declare repo X in the PRD".
- **One brain, N worktrees.** One container, one pi session (decision 08
  continuity intact); worktrees are writable mounts under the run dir.
- **Bookkeeping PR** raised by `factory-run.sh` at **loop end — success or
  failure** — so evidence always persists; merged by the **user at UAT**
  (never auto-merged). Its diff must touch **only `docs/`**; a code path in it
  is a hard fail (the tripwire that replaces `git add -A`).
- **Per-repo revision.** On REQUEST_CHANGES only the repos whose PRs were
  rejected are revised (same branches, same session, decision 08); the
  revision cap is per task.
- **Loop state reads off the checkout.** Verdicts + review reports read from
  the run dir; the pickup gate checks for an open `[factory] <slug>` PR per
  declared repo via `gh`, so master lag can never cause re-implementation.
- **Run manifest** (JSON) is the monitoring backbone: per-repo
  `{branch, pr, verdict, state}`, `bookkeeping_pr`, `revisions`, `outcome`.
  Printed at the end of every run (success or failure), copied into the
  factory-traces bundle, mirrored into the bookkeeping PR body.
- **Retired:** the sync step's `git add -A` + `git push origin master`, and
  `merge-pr.sh`'s master push.

## User stories

1. A task whose PRD declares a single app repo raises exactly **2 PRs**: 1
   code PR in that repo (``factory:needs-review`) and 1 bookkeeping PR on the
   workspace root (``factory:bookkeeping`, docs-only).
2. A task whose PRD declares **N app repos** raises exactly **N+1 PRs**: N
   code PRs (one per repo, base = each repo's manifest branch) + 1 bookkeeping
   PR.
3. A task whose PRD declares **the workspace root only** raises exactly **1
   PR** containing both the code commits and the bookkeeping commits.
4. A **hybrid** task (root + app repos) raises 1 root PR (code + bookkeeping)
   + 1 app PR per app repo.
5. The **delivery invariant** holds after every delivery; a violation fails
   the run loudly (per-repo status printed, non-zero exit).
6. The **bookkeeping tripwire** holds: the bookkeeping PR diff touches only
   `docs/`; a code-path file in it fails the run loudly.
7. The **run manifest** is written for every run (success and failure), shown
   at the end, copied into the factory-traces bundle, and mirrored into the
   bookkeeping PR body.
8. The **pickup gate** skips any task with an open `factory/<slug>` PR in any
   declared repo (no re-implementation while in flight), printing a loud
   skip reason.
9. On REQUEST_CHANGES, **only the rejected repos** are revised (same branches,
   same original session); re-review covers just those PRs; the revision cap
   is per task.
10. `bin/merge-pr.sh` accepts the **PR set**, pre-flights all-open, merges
    each, records a Merge row per PR on the task file, and transitions the
    task to complete only when the **whole set** is merged.

## Implementation decisions

- **Repo declaration:** PRD header `**Repos:**` — comma-separated repo_map
  values; `.`/`workspace` = root. Absent → single repo derived from Task
  `**Project:**` (backward compatible with every existing PRD).
- **One brain**: a single container / session with N writable worktrees
  (never N containers) — preserves cross-repo coherence and session
  continuation across respawns and revisions.
- **Bookkeeping PR raised by `bin/factory-run.sh` at loop end** (success or
  failure), merged by the user at UAT, never auto-merged.
- **Shape B collapse = separate commits** on the same root branch: one code
  commit, then one bookkeeping commit — reviewers see code and docs
  separately; the PR diff contains both.
- **Per-repo revision** (only REQUEST_CHANGES'd repos); cap per task.
- **Loop reads run dir, not the checkout:** review archives are written to
  the run dir during the run; verdict read-back, `read_verdict`, and the
  revise leg's `resolve_review_report` switch from checkout paths to
  `RUN_DIR/...` paths. The repo copy lands only via the bookkeeping PR.
- **Gate:** `gh pr list --search "[factory] <slug>" --state open` on every
  declared repo, in addition to the existing PRD-Final + task-prd-ready check.
- **Branch naming:** `factory/<slug>/<repo-key>/<ts>` (repo-key = repo_map
  value dir, `workspace` for root); bookkeeping `factory/<slug>/bookkeeping/<ts>`.
- **Backward compatibility:** existing single-repo PRDs keep the old flow
  (one code PR) but gain the bookkeeping PR; the sync stop's direct push is
  retired for ALL shapes.

## Testing decisions

- Extend the existing driver suites' seams (they already mock
  `IMPLEMENTER_GH_BIN`/`IMPLEMENTER_PODMAN_BIN`/`REVIEWER_GH_BIN`): fixtures gain
  a 2-repo `repo_map` and PRDs carrying `**Repos:**` so each PR shape is
  exercised with no real remote.
- `test-implementer-driver.sh`: repo-set resolution (unknown repo → exit 2
  naming it), per-worktree delivery (2 dirty worktrees → 2 push + 2
  `gh pr create` calls), Shape B collapse (root worktree gets code commit then
  bookkeeping commit), the A/B invariant assertion (violation → loud fail),
  and the bookkeeping tripwire (a bookkeeping commit touching `bin/` → fail).
- `test-factory-run.sh`: headless loop over a 2-PR set (stubbed reviewer),
  REQUEST_CHANGES on one PR → revise only that repo, per-task cap exhaustion,
  bookkeeping PR raised on both success and failure, manifest content + print.
- `test-review-driver.sh`: PR-set resolution, run-dir report/verdict path
  (no checkout archives).
- `test-merge-pr.sh`: multi-PR pre-flight (one already merged → abort with the
  split); per-PR Merge rows; complete transition only when the whole set is
  merged.

## Architecture

### Data flow (per run, headless loop)

```
PRD (**Repos:**) ── resolve_repo_set ──▶ repo keys + local checkouts (validation, fail-fast)
        │
        ▼
prepare_run_dirs ──▶ RUN_DIR/worktrees/<repo-key>/ (one clone per repo)
        │
        ▼
run_container (ONE pi session; all worktrees writable; brief lists repo↔worktree map)
        │  outbox: report + decisions (+ "needs undeclared repo X" flag → fail loud)
        ▼
deliver: per worktree-with-changes → commit → push factory/<slug>/<repo>/<ts> → gh pr create
        │        (Shape B: when root ∈ touched-set, code commit FIRST, bookkeeping commit SECOND on the root branch)
        ▼
assert_delivery_invariant (A/B XOR) — violation → fail loud
        │
        ▼
review per code PR (review-run.sh <pr>...) → verdict per PR → manifest.repos[].verdict
        │
        ├── any REQUEST_CHANGES → implementer-run.sh --revise <only those PR> (same branches/session) → re-review → cap/exit
        │
        ▼ (APPROVE or cap/failure)
raise_bookkeeping_pr (run end, ALWAYS): branch factory/<slug>/bookkeeping/<ts> from master
   ├── docs-only tripwire check
   └── body = manifest table + report(s)
        │
        ▼
print manifest + exit status (fail-loud = non-zero + per-repo table surfaced)
```

### PR shape matrix

| Shape | Root touched | Code PRs | Bookkeeping PR | Total PRs |
|---|---|---|---|---|
| A — single app | no | 1 (app repo) | 1 | 2 |
| A — multi app | no | N | 1 | N+1 |
| B — root only | yes | 1 (root: code+docs) | 0 | 1 |
| B — hybrid | yes | 1 root + (N−1) app | 0 | N |

### Run manifest schema (contract)

```json
{
  "task": "<slug>",
  "run_id": "<run-id or ts>",
  "outcome": "in-progress|approved|failed|cap-exhausted|skipped",
  "revisions": 2,
  "repos": {
    "goal-agent":               {"branch": "factory/<slug>/goal-agent/<ts>", "sha": "...", "pr": 12, "verdict": "APPROVE",   "state": "open"},
    "llamacpp_inference_server": {"branch": "factory/<slug>/llm/<ts>",           "sha": "...", "pr": 13, "verdict": "REQUEST_CHANGES", "state": "open"}
  },
  "bookkeeping_pr": 14,
  "root_code_pr": null,
  "trips": {"bookkeeping_docs_only": true}
}
```

### Delivery invariant (assert twice — min, after delivery, after loop end)

```
has_root_code_pr = "workspace" in repos && repos["workspace"].pr exists
has_bk_pr = manifest.bookkeeping_pr exists
assert (has_root_code_pr && !has_bk_pr) || (!has_root_code_pr && has_bk_pr)
```

### Failure-mode table (fail-fast / fail-loud)

| # | Failure | Fast | Loud |
|---|---|---|---|
| F1 | undeclared/unavailable repo at resolve | exit 2 pre-implementation | names the repo |
| F2 | partial delivery (PR A pushed, PR B push failed) | after each push, assert all | partial archive + revert + per-repo status |
| F3 | bookkeeping PR create fails | yes | code PRs up, evidence stranded — re-raiseable |
| F4 | tripwire: bookkeeping diff touches code | yes | hard fail (the bdac29e class, closed) |
| F5 | gate sees open factory/<slug> PR | yes | loud skip |
| F6 | REQUEST_CHANGES persists after cap | loop exit non-zero | last report per PR surfaced |
| F7 | merge-pr.sh on a stale/partial set | pre-flight | never double-merge |

## Program Design

### Call-stack tree (changed paths only)

```
bin/factory-run.sh --headless --task <slug>
 ├─ gate: Final PRD + prd-ready + no open [factory] <slug> PR ($gh per repo)
 ├─ implementer-run.sh --task <slug>
 │    ├─ resolve_prd → resolve_repo_set          (PRD **Repos:** → repo_map → validation)
 │    ├─ prepare_run_dirs                        (N worktrees; per-repo manifest branch)
 │    ├─ run_container (singular; all worktrees visible)
 │    ├─ deliver: for each dirty worktree → commit → push factory/<key>/<ts> → gh pr create
 │    │     (Shape B: root branch gets code commit then bookkeeping commit)
 │    ├─ assert_delivery_invariant
 │    └─ update manifest (per-repo pr/verdict)
 ├─ review-run.sh <PR1> [<PR2> ...]   → per-PR verdict; manifest update
 └─ raise_bookkeeping_pr (always at end) + print manifest / mirror into PR body
bin/review-run.sh <pr-set>: resolve_prset, review-repo (diff base…head), report→run-dir, comments, verdicts
bin/merge-pr.sh <pr> [<pr>...]: pre-flight all open → merge each → Merge rows → task complete
.github/workflows/factory.yml: gate (gh open-PR), replace sync step with prompt (bookkeeping PR already raised by loop); bundle manifest
```

### File-tree diff (expected)

```
bin/implementer-run.sh        +resolve_repo_set, +prepare_run_dirs, deliver per-repo, Shape B collapse
bin/review-run.sh             PR-set resolution, run-dir archives + verdicts
bin/factory-run.sh            loop over PR set, bookkeeping PR creation, manifest print
bin/merge-pr.sh               multi-PR pre-flight/merge/complete
bin/lib-pr-tracking.sh        (rows now can span multiple code PRs — verify schema)
bin/test-*.sh (4 suites)      plus new multi-repo fixtures
.github/workflows/factory.yml gate + sync-step replacement
docs/reference/implementer-agent.md, reviewer-agent.md   (artefact maps updated)
docs/tasks.txt                (+ Multi-repo delivery task … existing shape)
config/implementer.json       validate **Repos** against repo_map (no change to map itself)
```

### Key types / functions

- `resolve_repo_set(prd) → repo_key[]` (mandatory `**Repos:**` parsed, validated against `repo_map`, local `.git` presence; default → Task project)
- `assert_delivery_invariant(manifest) → 0|die` (the A/B XOR)
- `raise_bookkeeping_pr(manifest, run_dir) → pr_url` (docs-only; tripwire: `git diff-tree --name-only` every changed file must start with `docs/`)
- `repos[].verdict` per PR; `overall = all APPROVE`

## Location (file map)

| Change | Path |
|---|---|
| Repo-set resolution, N worktrees, per-repo delivery, Shape B, invariant | `bin/implementer-run.sh` |
| PR-set review, run-dir report/verdicts | `bin/review-run.sh` |
| Loop over PR set, bookkeeping PRs, manifest print | `bin/factory-run.sh` |
| Multi-PR merge + complete transition | `bin/merge-pr.sh` |
| PR-tracking rows for multiple PRs | `bin/implementer-run.sh` / `bin/lib-pr-tracking.sh` |
| Gate + sync step → bookkeeping PR | `.github/workflows/factory.yml` |
| Fixtures + assertions | `bin/test-*.sh` |
| Artefact maps | `docs/reference/*.md` |

## Acceptance (verification)

```bash
bash bin/test-implementer-driver.sh   # repo-set, per-worktree delivery, Shape B, invariant, tripwire
bash bin/test-review-driver.sh        # PR-set review, run-dir verdicts
bash bin/test-factory-run.sh          # loop over set, bookkeeping PR raise + manifest
bash bin/test-merge-pr.sh             # pre-flight + multi-merge + complete
```

Plus a **live smoke**: one real task with a two-repo PRD through `bin/factory-run.sh --headless` on a scratch branch — assert exactly N code PRs + 1 bookkeeping PR, invariant holds, manifest printed, loop stops at APPROVE. Manual UAT-completion pass `bin/merge-pr.sh <set>`.

## Out-of-scope

- Monorepo collapse (un-ignore app dirs) — deliberately rejected (decision record).
- Auto-merge of the bookkeeping PR — deferred; user merges at UAT.
- Moving lifecycle state out of git (state store) — future.
- Org-level GitHub policies / branch protection (companion task `branch-protection-merge-only`).
- Required approving reviews > 0 or CI status gates on PRs.

## Further notes

This task is itself a workspace-root-only task (`repos: workspace`) — it
implements Shape B (root PR with code + bookkeeping) end-to-end on the live
factory, and doubles as the dogfood for the new bookkeeping stream. Land the
`branch-protection-merge-only` workspace enforcement only after this task
completes (the sync step must be retired first).