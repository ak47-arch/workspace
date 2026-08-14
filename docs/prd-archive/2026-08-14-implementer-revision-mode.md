# PRD: Implementer revision mode — `--revise <pr>` resumes the original session to address review findings

**Date**: 2026-08-14
**Status**: Final
**Owner**: software-factory
**Task**: implementer-revision-mode
**Session**: `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/08-implementer-revision-same-session.md`

## Problem statement

When a review returns REQUEST_CHANGES (e.g. PR #2 `implementer-ponytail`, report
`docs/code-reviews/2026-08-14-implementer-ponytail/report.md`), nothing in the
factory can fix it autonomously: the reviewer is read-only (decision 03), the
operator hand-editing the branch is the status quo (code-review-agent precedent),
and `implementer-run.sh` has no revision path — `--resume` is reserved but
unimplemented, and a normal run would raise a **new** PR instead of amending the
open one.

Decision 08 fixes the identity question: the implementer must fix, **resuming its
original implementation session** (same `--session-id`/`--continue` semantics,
same branch) so the code context, its own decision records, and the task lineage
survive — with the reviewer report injected as **binding authority** to mitigate
the author's confirmation bias.

## Solution overview

Add a `--revise <pr>` mode to `bin/implementer-run.sh`. It resolves the open PR
to its task slug and the original implementation session UUID (from the task's
decision-06 PR tracking), reconstructs a run dir whose worktree is the **same
branch** and whose `sessions/` is **seeded with the original pi session file**
(continuity source for `--continue`), mounts the review report + decisions as the
fix spec, runs the container with a revision directive (findings binding, no
restart, no re-litigate), then delivers by **pushing to the same branch** — no
new PR, no task transition — and records a `Revised:` row on the task.

## Architecture

### Data flow (one revision)

```
bin/implementer-run.sh --revise <pr>
  → resolve_revision:  PR (url|repo#num|bare#) → slug (PR title "[factory] <slug>:"
                       or task PR tracking) → original impl session UUID
                       (task PR tracking "Raised by: implementer run <uuid>")
                       → review report+decisions (newest docs/code-reviews/*-<slug>/
                       that has a REQUEST_CHANGES verdict; die if none)
  → prepare_revision_dir:
        RUN_DIR = $RUNS_ROOT/<slug>-<ts>   (new, ephemeral)
        worktree: clone $WORKSPACE/$TARGET_REPO; fetch; checkout -B <same-branch>
                  origin/<same-branch>   (branch name read from the PR head ref)
        sessions/: copy docs/knowledge/sessions/<orig-uuid>/session.jsonl →
                  RUN_DIR/sessions/<ts>_<orig-uuid>.jsonl  (pi-native naming)
        review/: copy report.md + decisions/*.md → RUN_DIR/review/
        brief.md (revision variant, see below)
  → run_container (REVISION directive; sess_args=(--session-dir /sandbox/sessions
                  --continue) from attempt 1; same pi invocation shape: ponytail
                  skills, persona, model)
  → deliver_revision:  commit fix on the same branch; git push origin <same-branch>
                  (updates PR #N); NO gh pr create; gh pr comment noting revision;
                  append "- Revised:" row to task PR tracking; archive
                  revision-<n>-report.md; finalize_session_copy (same UUID dir);
                  cleanup run dir (durable kept). No transition: task stays
                  in-review until the re-review.
```

### Contracts

- **Input**: an open PR (`<url> | owner/repo#num | repo#num | bare#`). Must be
  open and not merged — else `die` (exit 2). Slug derived from the PR title
  `[factory] <slug>: …` (same convention as `merge-pr.sh`).
- **Session continuity**: pi's `--continue` + `--session-dir` resumes a
  conversation from the session file in that dir (the mechanism already used for
  container respawn, `implementer-run.sh` ~363-367). The revision seeds that dir
  with the original session's file — the durable copy
  `docs/knowledge/sessions/<uuid>/session.jsonl` **is** the pi-native file
  (finalized by `finalize_session_copy`, ~696-714).
- **Fix spec**: `/sandbox/review/report.md` + `/sandbox/review/decisions/` are
  the binding authority; the revision directive states findings win over prior
  reasoning (decision 08 mitigation).
- **Branch semantics**: the fix commits ride on top of the existing PR branch;
  push is a normal fast-forward push (the branch already exists on origin).
- **Data model** — PR tracking schema (decision 06) gains an append-only row:
  `- Revised: <head-sha> (<date>, impl session <uuid>, addressing review <r-session>)`
  where `<r-session>` comes from the task's own `Review: session <uuid>` row.
  Revision archives land in the **same** implementation dir:
  `docs/implementations/<date>-<slug>/revision-<n>-report.md` (v1 stays
  `report.md`); the revision session extends the **same**
  `docs/knowledge/sessions/<orig-uuid>/session.jsonl`.

## User stories

- **US1 — resolve + reconstruct**: `--revise <pr>` resolves PR → slug → original
  impl session UUID → newest REQUEST_CHANGES review report+decisions, and
  reconstructs the run dir (same-branch worktree, seeded `sessions/`, mounted
  `review/`, revision brief). Errors: closed/merged PR → exit 2; unresolvable
  slug → exit 2; no REQUEST_CHANGES review report → exit 2. (Done when the run
  dir contains the same branch, the original session file, and the review
  report; `--dry-run` proves it WITHOUT launching a container — revise-mode
  dry-run stops after `prepare_revision_dir` and simulates the pi invocation.)
- **US2 — continuation + revision directive**: the container runs with
  `--continue` + the seeded session from attempt 1 and a revision directive
  (fix exactly what the findings scope; findings win over prior reasoning; no
  restart from scratch; no re-litigation; no scope expansion; no git — host
  owns it). (Done when the pi invocation carries `--continue` and the directive
  text encodes the binding-authority rule.) Continuity is verified
  **mechanically** (seeded file present + `--continue` in the invocation + a
  vacuous-guard test); semantic recall strength is a known risk tracked by
  decision 08's revision trigger, not asserted here.
- **US3 — delivery on the same PR**: revision delivery commits the fix on the
  same branch, pushes `origin/<branch>` (updating PR #N), posts a PR comment
  noting the revision, and does **not** call `gh pr create`. Task stays
  `in-review` (no transition). (Done when a mock-gh log shows a push + comment
  and **no** `pr create`.)
- **US4 — bookkeeping**: revision report archived as
  `docs/implementations/<date>-<slug>/revision-<n>-report.md`; the same
  `IMPL_UUID` session file is extended and its knowledge copy refreshed; the
  task PR tracking gains the `Revised:` row; run dir cleaned (durable kept).
  (Done when all four artifacts exist and the index is updated.)
- **US5 — tests**: `bin/test-implementer-driver.sh` gains revise-mode coverage:
  (a) `--revise <pr> --dry-run` smoke — exit 0, run dir has seeded session +
  mounted report + same branch, no new UUID; (b) non-dry smoke with mock
  `gh`/`podman` — asserts same-branch push, no `pr create`, `Revised:` row, task
  unchanged; (c) negatives — closed/merged PR and missing review report both
  exit 2; (d) full factory sweep stays green. (Done when the suite passes with
  the new tests and all other suites remain green.)

## Implementation decisions

- **D1 — reuse the original IMPL_UUID**: one session identity, one knowledge
  file, one lineage (decision 08). No new UUID in revise mode.
- **D2 — binding-authority directive**: the revision directive explicitly
  outranks the session's prior reasoning ("where findings conflict with your
  earlier reasoning, the findings win") — the confirmation-bias mitigation.
- **D3 — no task transition during revision**: the task stays `in-review`
  through the revision; the re-review re-affirms or re-blocks. Revision is not
  "being implemented" in the lifecycle sense. The revise branch of `main`
  therefore **never calls `transition`** (a real trap: v1 main calls it
  unconditionally at ~675 and ~721 — the revise branch must skip both) and
  never generates a fresh `new_uuid` (D1) nor calls `push_and_pr` (D4).
  (The "Bookkeeping (via transition tooling)" file-map entry refers to THIS
  task's own lifecycle as it flows through the gate — not a transition during
  a revision.)
- **D4 — no new PR, no merge**: delivery pushes the existing branch only.
  Merge remains operator-gated (decision 07); reviewer stays read-only
  (decision 03).
- **D5 — revision archive into the same dir**: `revision-<n>-report.md` next to
  v1 `report.md`, keeping one implementation dir per task lineage. A follow-up
  may extend `eval-pipeline.py` to read `revision-*` files (out of scope here).
- **D6 — session seed naming**: copy the durable session file as
  `<ts>_<orig-uuid>.jsonl` in the seeded `sessions/` dir (pi's own naming
  convention); `--continue` finds it there.
- **D7 — `--resume` stays reserved**: `--revise` absorbs the session-continuity
  mechanics `--resume` would have used; do not implement `--resume` here.
- **D8 — dependency**: the mocked-podman smoke needs the `IMPLEMENTER_PODMAN_BIN`
  seam from the implementer-ponytail task (PR #2). Implement this task after
  that PR merges; if it has not merged, add the seam as part of this task
  (mirroring `review-run.sh` `podman_call`) rather than blocking.

## Testing decisions

- Extend `bin/test-implementer-driver.sh` with revise-mode fixtures: a fixture
  task file with PR tracking (Raised by + PR rows), a fixture original session
  file, a fixture review report (REQUEST_CHANGES), mock `gh` (pr view → title →
  slug; pr create must be absent from the log), mock `podman` via
  `IMPLEMENTER_PODMAN_BIN` writing a revision report.
- Positive + negative cases as US5; a vacuous-smoke guard: removing the
  `--continue` seed must fail the smoke.
- Full sweep must stay green: implementer, review (61), factory-run (22),
  merge-pr (8), transition (45).

## Out of scope

- `--resume` (reserved, D7); auto-trigger of revisions (manual trigger only).
- Any change to `bin/review-run.sh`, the reviewer persona, or the merge tool.
- The actual PR #2 revision — that is the **first real use** of this mode after
  it ships (UAT hand-off), not part of this task.
- `eval-pipeline.py` revision-report reading (follow-up); task lifecycle
  transition changes.

## File map

- `bin/implementer-run.sh` — `--revise` arg; `resolve_revision`; `prepare_revision_dir`;
  revision directive; `deliver_revision` (same-branch push, no pr create,
  `Revised:` row, comment); archive + cleanup paths; main-flow branch.
- `bin/test-implementer-driver.sh` — revise-mode tests (US5).
- `bin/lib-pr-tracking.sh` — `Revised:` row helper (append-only, same schema).
- Bookkeeping (via transition tooling): `docs/tasks/implementer-revision-mode.md`,
  `docs/tasks.txt`.

## Acceptance — how "done" is proven

1. `bash -n bin/implementer-run.sh`.
2. `bash bin/test-implementer-driver.sh` → all pass including the new
   revise-mode tests.
3. Full sweep green: implementer, review (61), factory-run (22), merge-pr (8),
   transition (45). (Known wobble: the implementer suite may be 33/34 without
   the gitignored `workspace_restore_manifest.json` — a pre-existing
   environmental failure unrelated to this task; the implementation must stay
   robust to it.)
4. `--revise <fixture-pr> --dry-run` exits 0 and the run dir proves: same
   branch checked out, seeded `sessions/` containing the original session file,
   `review/` mounted, and `--continue` in the (simulated) pi invocation.
5. Mock-gh log proves: push to the existing branch, PR comment, **no**
   `pr create`, `Revised:` row on the task file.

## Context pointers

- Decision 08 (identity + binding authority): `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/08-implementer-revision-same-session.md`
- Decision 06 (PR tracking schema): `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/06-task-pr-tracking.md`
- Working reference: `bin/implementer-run.sh` (`--resume` line 115, `prepare_run_dir`
  205-310, `run_container` 337-460, `push_and_pr` 514-592, `cleanup_run_dir`
  603-640, main 668-740); `bin/review-run.sh` `--continue` precedent (~506-510);
  `bin/merge-pr.sh` slug-from-title convention.
- First real target: PR #2 `implementer-ponytail` review
  `docs/code-reviews/2026-08-14-implementer-ponytail/report.md`.
