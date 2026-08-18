# Implementer REVISION Report — multi-repo-delivery-bookkeeping-prs

- **PR**: ak47-arch/workspace#12 · **Task**: multi-repo-delivery-bookkeeping-prs
- **Impl session UUID**: `4d89a859-9d05-4b28-9efd-e56aad8837e7`
- **Worktree**: `/sandbox/worktree` (same branch; no git commands run by the implementer)
- **Binding authority**: `/sandbox/review/report.md` (verdict REQUEST_CHANGES, findings B-1…B-5 + J2/J3) + `/sandbox/review/decisions/01-…invariant-assert-point.md`
- **Outcome**: all 5 blocking findings + the J2/J3 conformance items fixed, in scope. **229 tests pass across 4 suites, 0 failures.**

## Verification (PRD acceptance commands)

| Suite | Result |
|-------|--------|
| `bin/test-implementer-driver.sh` | **85 passed, 0 failed** (exit 0) |
| `bin/test-review-driver.sh`      | **66 passed, 0 failed** (exit 0) |
| `bin/test-factory-run.sh`        | **59 passed, 0 failed** (exit 0) — was 49; +10 for B-1/B-3/B-5/US9 |
| `bin/test-merge-pr.sh`           | **19 passed, 0 failed** (exit 0) |

All modified scripts pass `bash -n`.

## Fixes (mapped to the blocking findings)

### B-1 (US2/US4) — Shape A invariant false-fail, assert point moved — FIXED
- `bin/implementer-run.sh` `assert_delivery_invariant` is now **delivery-time** (per review decision 01): for Shape B (root in set) it requires a root code PR and no bookkeeping PR; for **Shape A (root not in set) it holds** (bookkeeping pending at loop end) — no more false-fail of a legitimate multi-app delivery.
- Added **loop-end re-assert of the full A/B XOR** in `bin/factory-run.sh` (`assert_loop_end_invariant <manifest>`), run after `finish_bookkeeping` in both headless (`finalize_headless`) and non-headless paths; fails loud (exit non-zero) on a violated Shape (e.g. Shape A whose bookkeeping PR failed to raise → "neither"). `root_code_pr`/`bookkeeping_pr` come from the run manifest — the one place both sides exist.
- **Evidence**: implementer-driver invariant tests rewritten for delivery-time semantics (+ Shape A no-false-fail); factory-run tests "loop-end invariant asserted + holds (Shape A)" and "loop-end invariant violation → exit 1".

### B-2 (US8) — pickup gate wired into the live path — FIXED
- `.github/workflows/factory.yml`: added a **"Pickup gate (skip if an open [factory] PR exists)"** step (gh + PAT, checks every declared repo from the PRD `**Repos:**`, default root) and gated the "Run headless factory loop" step on it (`env.FACTORY_SKIP_PICKUP != 'true'`); the loop step now also exports `FACTORY_GH_BIN: gh` + `FACTORY_ROOT_REPO` so the in-script `pickup_gate()` is LIVE.
- `bin/factory-run.sh` `pickup_gate()` now **self-resolves `FACTORY_REPOS`** from the PRD `**Repos:**` header against the local checkouts' GitHub origins (`gate_repos_for`, `gh_owner_repo`), so the gate works locally and in CI with no env seam.
- **Evidence**: existing "pickup gate: open factory PR → loud skip, exit 0" test still passes; self-resolution exercised via `gate_repos_for` (defaults to root when no header).

### B-3 (US1/2/4/7) — bookkeeping PR never raised live (BK_MANIFEST seam inert) — FIXED
- `bin/factory-run.sh` `finish_bookkeeping` defaults `BK_MANIFEST` to the implementer's run manifest: `BK_MANIFEST="$(factory_manifest "$slug")"` (locates `<runs_root>/<slug>-*/manifest.json`). A real Shape A run now raises the bookkeeping PR and mirrors the manifest without any env wiring.
- **Evidence**: new test "BK_MANIFEST defaulted to run manifest" + "bookkeeping gh pr create invoked" + "manifest bookkeeping_pr mirrored" (exit 0) with `BK_MANIFEST` unset.

### B-4 (US9) — multi-PR headless review/revise loop — FIXED
- `bin/factory-run.sh` headless loop now derives the **PR set** from the run manifest (`resolve_run_ctx` → `PR_SET`), reviews the whole set once, reads per-PR verdicts, and **revises ONLY the rejected repos** (`revise_pr` per rejected PR), then re-reviews only those rejected — passing the cap logic unchanged.
- `bin/review-run.sh` accepts a **PR set** (`<pr> [<pr2> …]`): each PR is reviewed in its own process (single-PR path byte-identical for a single arg) and its verdict is **merged into `$REVIEWER_SET_VERDICTS`** (`repo#num → verdict`), which the loop reads. Exit 0 only when every PR approves.
- **Evidence**: new factory-run **US9 test** — 2-PR manifest, PR 12 rejected once → exactly `implementer --revise 12` (NOT 11), 2 reviews (initial pass + re-review of 12), all-approve → exit 0, bookkeeping raised.

### B-5 (US7 mechanics) — bookkeeping branch never reached GitHub; swallow; trap — FIXED
- `bin/factory-run.sh` `raise_bookkeeping_pr`: the scratch clone's origin is now re-pointed at the real GitHub remote (`git -C "$clone" remote set-url origin "$real_url"` where `$real_url` = root's origin), so the branch + PR actually reach GitHub. Removed `trap 'true' ERR` override and the unused `local rc=0` (J3).
- The `gh pr create` failure is now **fail-loud**: empty URL → `FAILED: bookkeeping gh pr create returned no URL … run aborted` + non-zero return propagates through `finish_bookkeeping` and `finalize_headless`, so a failed bookkeeping PR is no longer silently swallowed (F3).
- The manifest's `bookkeeping_pr` is patched (`set_manifest_bookkeeping_pr`) after a successful raise, so story-7 mirroring + the loop-end invariant see the real PR number.

## Conformance items (J2/J3)

- **J2 verdict read-back → RUN_DIR**: `read_verdict` now reads the reviewer run-dir verdict first (`<review run dir>/reports/verdict.txt` via `review_run_dir`), falling back to the checkout archive for stub-driven tests. The PRD-mandated RUN_DIR path is the primary source.
- **J3 trap-err/local-rc**: removed the global ERR-trap override and the unused `local rc=0` in `raise_bookkeeping_pr`; bookkeeping + invariant failures now fail loud.

## Advisory items (review "consider" — left as-is deliberately)

- `print_manifest` defined in both implementer and factory (divergent) and the `repo_map_has_value` no-jq fallback: both are advisory over-engineering notes, not blocking; kept to avoid scope creep / no-jq regression risk. Not part of the REQUEST_CHANGES blocking scope.

## UAT hand-off list (cannot be proven in the sandbox)

1. **Live CI run** (no sandbox network): confirm the new workflow "Pickup gate" step + `FACTORY_GH_BIN` env and the retired direct-push sync step behave on a scratch task on `master`.
2. **Real two-repo live smoke** through `factory-run.sh --headless`: assert N code PRs + 1 bookkeeping PR, the bookkeeping branch appears on GitHub (B-5 origin fix), the manifest renders in the PR body, and the loop stops at APPROVE. This is now possible because the Shape A invariant no longer false-fails and the bookkeeping seams are wired by default.
3. **Per-repo revision live**: force a REQUEST_CHANGES on one of several repos and confirm only that repo is revised + re-reviewed (US9).
4. **Shape B live**: confirm the root PR carries both the code and the (fresh-bookkeeping) report+manifest commits, replacing the deleted stale archive (review D3/D7 — the fresh archive lands via the dogfood run's Shape B bookkeeping commit).
5. Operator capstone (branch-protection PUT) — driver/operator-owned, unchanged.

## Emerged decision

`/sandbox/outbox/decisions/02-loop-end-delivery-invariant.md` — the delivery-time vs loop-end A/B XOR split, implemented to satisfy review decision 01 and B-1.