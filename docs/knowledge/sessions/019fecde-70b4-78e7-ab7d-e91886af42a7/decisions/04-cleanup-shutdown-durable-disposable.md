## Decision: Enforce disposable-vs-durable in the driver — container shutdown + automatic run-dir cleanup after delivery

**Status**: accepted
**Date**: 2026-08-13 01:50
**Task**: implementer-agent
**Project**: software-factory
**Session**: sessions/019fecde-70b4-78e7-ab7d-e91886af42a7/session.jsonl

### Context

The first live run left ~628 MB of residue in its run dir: `node_modules`
(193 MB) + `venv2` (78 MB) installed by the implementer to run its tests,
~322 MB of raw trace (streamed `session.jsonl` + `container-*.log`), and a
33 MB `.git`. The "disposable vs durable" rule existed in docs (decision 03)
but nothing enforced it: `implementer-run.sh` had no post-run cleanup and no
explicit container shutdown (relying only on `podman run --rm`).

### Problem

- Every future run would accumulate ~300 MB of throwaway dependency trees the
  same way — the host had no automatic reclamation step.
- The container was only implicitly removed via `--rm`; no named identity meant
  no way to deterministically stop/remove a run's container (e.g. one left
  behind after a host-side driver death).
- Two latent failure-path bugs were discovered while adding the fix:
  1. `finalize_session_copy` ran `native="$(ls -t "$RUN_DIR"/sessions/*.jsonl | head -1)"`;
     on a failed run the glob matches nothing → `ls` fails → `set -o pipefail`
     makes the pipeline non-zero → the variable assignment exits non-zero →
     `set -e` aborted the whole driver with a **silent exit 2** BEFORE
     `fail_run` — no FAILED message, no partial report archived.
  2. `write_env_file` used `${!name}` on allowlist entries; a glob entry like
     `LANGFUSE_*` (present in the test config) crashed with
     "invalid variable name".

### Alternatives

- **Manual cleanup per run.** Rejected: same labour + same forgetfulness that
  caused the 628 MB; the rule must be automatic.
- **Delete the whole run dir after delivery.** Rejected: outbox/report, compact
  session evidence, brief, and worktree source (with `.git`) are durable and
  useful for audit; only deps + raw logs are disposable.
- **Keep everything, compress raw logs.** Rejected: 322 MB of logs compress to
  tens of MB but remain redundant with the compact `sessions/` evidence copy
  and the finalized transcript in `docs/knowledge/sessions/<uuid>/`.

### Decision

1. **Name every run's container** (`impl-<IMPL_UUID>`) and add `stop_container()`:
   explicit `podman stop -t 5` + `podman rm -f` after the PR is raised (success)
   and on the failure path; stale containers swept at attempt start. Belt and
   suspenders over `--rm`.
2. **Add `cleanup_run_dir()`** — runs automatically once the PR is raised
   (success path) and on failure with `--keep-logs`:
   - Removes: `node_modules`, `venv*`, `.venv`, `__pycache__`, `.pytest_cache`,
     `*.pyc`, raw `container-*.log`, streamed `session.jsonl` transcript,
     `secrets.env` (re-injectable per run).
   - Keeps (durable): outbox report + decisions, compact `sessions/` evidence,
     brief, PR body, worktree source + `.git`.
3. **Toggles**: `cleanup_enabled` / `keep_worktree` in `config/implementer.json`;
   env overrides `IMPL_CLEANUP=false`, `KEEP_WORKTREE=0`.
4. **Fix both latent bugs**: guard the session-glob with `compgen` so a failed
   run reaches `fail_run` (exit 1 + partial report) instead of silent exit 2;
   skip non-identifier allowlist entries in `write_env_file`.

### Rationale

The durable-vs-disposable rule is only real if the code enforces it at the
delivery boundary. Automatic cleanup converts an ownership rule into behavior,
reclaims ~300 MB per task with zero labour, and never touches the durable
artifacts (outbox, evidence, brief, worktree). The named container makes the
cattle lifecycle explicit and killable. The two bug fixes close the "silent
loss / silent abort" failure class that has bitten the pipeline repeatedly.

### Consequences

- A completed run dir shrinks from ~628 MB to ~tens of MB (source + .git +
  outbox + evidence).
- Failure runs keep raw logs for diagnosis but strip deps; success runs are
  fully swept after the PR is raised.
- `docs/reference/implementer-agent.md` documents the cleanup contract.
- New tests: Test 6 covers disposable-vs-durable cleanup and `stop_container`
  no-op; suite grew 23 → 33, all passing; the integration failure path now
  asserts exit 1 + archived partial report (previously masked by the silent
  exit-2 abort).

### Revision triggers

- If `podman run` gains native per-run lifecycle management or the image
  switches to a shared npm/pip cache, the dep-stripping loop may become
  redundant — keep the rule, revisit the mechanism.
- If a debugger ever needs raw per-run logs by default, flip the default to
  keep them (current: removed on success; kept on failure).
- If the run-dir evidence copy becomes the ONLY copy of the transcript (e.g.
  knowledge-session copy removed), stop deleting `session.jsonl`.
