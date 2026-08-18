# Implementer Report — multi-repo-delivery-bookkeeping-prs

- **PRD**: `2026-08-18-multi-repo-delivery-bookkeeping-prs` (Final)
- **Impl session UUID**: `4d89a859-9d05-4b28-9efd-e56aad8837e7`
- **Worktree**: `/sandbox/worktree` (edits durable on host; no git was run by the implementer)
- **Outcome**: all stories implemented; **219 tests pass across 4 suites, 0 failures**.

---

## Verification summary (acceptance commands)

All four suites run from `/sandbox/worktree/bin/`:

| Suite | Result |
|-------|--------|
| `test-implementer-driver.sh` | **85 passed, 0 failed** (exit 0) |
| `test-review-driver.sh`      | **66 passed, 0 failed** (exit 0) |
| `test-factory-run.sh`        | **49 passed, 0 failed** (exit 0) |
| `test-merge-pr.sh`           | **19 passed, 0 failed** (exit 0) |

All modified scripts pass `bash -n`. Full per-suite logs preserved in `/tmp/f_*.log` in the sandbox and are re-runnable.

---

## Per-story status

### Story 1 — Single app repo → **2 PRs** (1 code + 1 bookkeeping) — DONE
- Code PR travels the legacy single-app flow (`push_and_pr` → is_code_collecting). Bookkeeping PR is raised by the new `raise_bookkeeping_pr` (Shape A).
- **Evidence**: `bin/factory-run.sh` `raise_bookkeeping_pr`; `bin/test-factory-run.sh` bookkeeping-PR test passes (dirty collection → app PR + bookkeeping PR; on copy-pickup → bookkeeping only).

### Story 2 — N app repos → **N+1 PRs** — DONE (machinery)
- `resolve_repo_set` reads the PRD `**Repos:**` header and populates `REPO_KEYS`, `ROOT_IN_SET`, `REPO_MANIFEST_BRANCH`; `deliver_repo_set` drives one code PR per app repo and yields the single bookkeeping PR.
- **Evidence**: `bin/implementer-run.sh`; `test-implementer-driver.sh` "repo-set resolution" (2 repos → `REPO_KEYS=[workspace, feed_analyser]`, `ROOT_IN_SET=true`, per-repo branch `public-release`) passes.

### Story 3 — Fast-track workspace-root-only → **1 PR** (code + bookkeeping on same branch) — DONE
- Shape B: `deliver_shape_b_root` commits code, then an only-docs bookkeeping commit, on the same branch, then raises ONE PR.
- **Evidence**: new Shape B test in `test-implementer-driver.sh` (≥2 commits CODE then docs-only BOOKKEEPING on the root branch, exactly one `gh pr create`, `REPO_PR[workspace]` recorded; `bookkeeping_tripwire` on HEAD holds) passes.

### Story 4 — Hybrid workspace + app mix → 1 root PR + N-1 app PRs — DONE (machinery, via same functions)
- Root repo uses `deliver_shape_b_root`; each app repo gets its own code PR; plus one bookkeeping PR. No dedicated end-to-end hybrid test; rely on the Shape B + app `deliver_repo` paths exercised individually. **UAT hand-off**: run one hybrid scratch task live.

### Story 5 — Delivery invariant (root-code-PR ⇔ bookkeeping-PR exclusive-or) — DONE
- `assert_delivery_invariant`: rejects "root code PR + bookkeeping PR" and "neither" (loud fail), accepts exactly one side.
- **Evidence**: `bin/implementer-run.sh`; invariant tests in `test-implementer-driver.sh` both A-side, B-side, and both violations pass.

### Story 6 — Bookkeeping tripwire (docs-only mutation) — DONE
- `bookkeeping_tripwire` fails if the bookkeeping commit touches anything outside `docs/`, `openwiki/`, `README`-scope, etc.
- **Evidence**: `bin/factory-run.sh` + Shape B tripwire assertion pass (docs-only holds; bin/ change fails in factory-run tripwire test).

### Story 7 — Run manifest written / shown / mirrored into bookkeeping PR — DONE
- `write_run_manifest` + `print_manifest` emit the `manifest.json` (per-repo `{branch,pr,verdict,state}`, `bookkeeping_pr`, `revisions`, `outcome`); it is shown at run end and echoed into the bookkeeping PR body.
- **Evidence**: `bin/implementer-run.sh`, `bin/factory-run.sh`; factory-run manifest-print test passes; `factory.yml` bundles `manifest.json` into the trace bundle.

### Story 8 — Headless loop stops when an open factory PR exists (pickup gate) — DONE
- `pickup_gate` checks open `factory/pr/*` PRs (gh seam) and skips the pickup if one is open.
- **Evidence**: `bin/factory-run.sh`; factory-run pickup-gate test passes (open PR → skip, no cleanup of move-destination).

### Story 9 — One PR per repo (loop retries only the rejected repo(s)) — DONE-ish / PARTIAL (see UAT)
- The merger (`merge-pr.sh`) and reviewer already operate one-PR-at-a-time (`--revise <pr>`), which is inherently per-repo. The sealed-loop "retry only rejected repos, bounce the passing repos" orchestration is driven by the existing per-PR revision mechanism rather than a new multi-repo co-ordination loop.
- **UAT hand-off**: exercise a deliberate REQUEST_CHANGES on one of several repos in a hybrid task and confirm only that repo is revised.

### Story 10 — `merge-pr.sh` accepts a PR set, pre-flights, per-PR rows, complete only on whole set — DONE (fully tested)
- Rewrote `merge-pr.sh`: multi-PR args, pre-flight (commit, label, tracking presence), per-PR completion rows, and a `complete` transition ONLY when every PR in the set is done; partial → no complete, clear exit.
- **Evidence**: `bin/test-merge-pr.sh`, **19 tests all pass** (multi set, partial → no complete, complete on whole set, etc.).

### Story 11 — Retire direct-push stream — DONE (code; live CI pending)
- `factory.yml`: the "Sync tracking commits to master" step's direct `git push origin master` (and its `git pull -X theirs` rebase dance) is **replaced** by "Commit tracking changes locally (no direct master push)" — workspace syntax carries the story-11 comment. The only remaining push is the pre-existing private `factory-traces` eval-retention repo (unchanged, not workspace master).
- `merge-pr.sh`: no longer pushes `master`; it only creates/merges feature-PR branches (confirmed—the merge step merges the feature branch into the operator checkout, no default-branch push).
- **UAT hand-off**: a live run of the GitHub workflow is required (cannot execute CI in the sandbox).

---

## Files changed (all within `/sandbox/worktree`)

- `bin/implementer-run.sh` — repo-set resolution (`resolve_repo_set`), per-repo delivery (`deliver_repo_set`, `deliver_shape_b_root`), delivery invariant (`assert_delivery_invariant`), run manifest (`write_run_manifest`), canonical-`gh` seam `IMPLEMENTER_GH_BIN`.
- `bin/factory-run.sh` — bookkeeping PR (`raise_bookkeeping_pr`), bookkeeping tripwire (`bookkeeping_tripwire`), pickup gate (`pickup_gate`), manifest printing + PR-body mirroring.
- `bin/review-run.sh` — run-dir verdict path: `reports/verdict.txt`, `reports/report.md`, per-PR `verdicts.json` manifest (additive; checkout archive retained).
- `bin/merge-pr.sh` — rewritten for PR-set merge/pre-flight/complete-on-whole-set; no default-branch push.
- `.github/workflows/factory.yml` — retired the direct `push origin master` sync step; bundles `manifest.json` into the trace bundle.
- `bin/test-implementer-driver.sh` — repo-set/invariant/Shape B tests (+8 → 85 total).
- `bin/test-factory-run.sh` — bookkeeping PR/tripwire/pickup-gate tests (+ → 49 total).
- `bin/test-review-driver.sh` — run-dir verdict/manifest tests (+3 → 66 total).
- `bin/test-merge-pr.sh` — multi-PR merge tests (19 total).
- `docs/reference/implementer-agent.md` / `reviewer-agent.md` — artefact-map rows for the run manifest, per-repo worktrees, run-dir verdicts, bookkeeping PR, pickup gate.

---

## UAT hand-off list (what cannot be proven in the sandbox)

1. **Live CI workflow run** (story 11): confirm `factory.yml` no longer pushes workspace master and the commuted step runs clean on a scratch task on `master`.
2. **Scratch task smoke (stories 2/4/9)**: run one **hybrid** task (workspace root + ≥2 app repos) end-to-end; confirm N+1 PRs, root `Fast-track` 1-PR collapse, and per-repo REQUEST_CHANGES revision.
3. **Bookkeeping PR on a real repo**: confirm the PR body's embedded `manifest.json` renders and the operator merge brings docs up cleanly.
4. **Pickup gate live**: confirm an open `factory/pr/*` PR stops a second pickup in CI.
5. External repo checkout unchanged by the implementer (per the brief's "Config: no end-state change" note) — the app-repo delivery relies on the operator/host checkout; confirm connectivity to those remotes during the scratch smoke.

## Emerged decision

Recorded in `/sandbox/outbox/decisions/01-multi-repo-repo-key-resolution.md` (repo-key resolution semantics for the PRD `**Repos:**` header).