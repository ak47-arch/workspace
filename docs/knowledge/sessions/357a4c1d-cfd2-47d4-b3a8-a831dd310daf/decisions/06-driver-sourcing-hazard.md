## Decision: Driver-sourcing hazard — never run driver mains from a test shell

**Status**: accepted
**Date**: 2026-08-17 02:12
**Task**: [sandbox-credential-mounting](../../../../tasks/sandbox-credential-mounting.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The hazard is documented as an operational rule: never source a driver script (implementer-run.sh, review-run.sh) from an ad-hoc shell unless IMPLEMENTER_RUN_SOURCED/REVI

### Context

While verifying the auth.json credential fix (decision 04), a quick syntax/test attempt sourced `bin/implementer-run.sh` from a shell with a fake `HOME` and a test `auth.json`. The driver's source-guard (`IMPLEMENTER_RUN_SOURCED`) was not set, so **sourcing the file executed `main`** — in real `--pick` mode, with the fake key. The run picked `task-pickup-similarity-merge`, transitioned it to in-progress, failed at container boot, reverted to prd-ready, and left two noise commits plus a phantom session link on master.

### Problem

The driver scripts are both sourceable (for unit tests) and executable (they run `main` when invoked as a script). The source-guard pattern (`if [ "${IMPLEMENTER_RUN_SOURCED:-0}" != "1" ]; then main; fi`) means any `source` from an ad-hoc shell that forgets to export the guard runs the real driver against the real workspace. The test suites handle this correctly (fixture workspace + guard + mock binaries); an interactive test did not.

### Alternatives

- **Ignore it (one-off mistake)** — rejected: the failure mode is silent and destructive (real lifecycle commits, phantom sessions), and nothing in the drivers warns when `main` runs with a non-interactive-looking environment.
- **Fail-fast on unexpected environment** — rejected for now: the drivers are deliberately simple, and the guard + fixture conventions already exist; adding environment heuristics is over-engineering.
- **Document the hazard + rely on the existing guard convention** — accepted.

### Decision

The hazard is documented as an operational rule: **never source a driver script (`implementer-run.sh`, `review-run.sh`) from an ad-hoc shell unless `IMPLEMENTER_RUN_SOURCED`/`REVIEWER_RUN_SOURCED=1` is exported AND the workspace is a disposable fixture.** The sanctioned test path is the existing test suites (`bin/test-implementer-driver.sh`, `bin/test-review-driver.sh`), which set the fixture workspace, the guard, mock podman/gh, and `--dry-run`. The accidental run's damage was fully recovered by resetting the local branch to the pushed state (no PR, no branch, no remote pollution).

### Rationale

The factory already has the right machinery (source-guard + fixtures + dry-run); the failure was operator error in an ad-hoc verification. Documenting the rule costs nothing and prevents a repeat; adding runtime heuristics would complicate drivers whose job is deterministic orchestration. The recovery (local reset to pushed state) is safe because the drivers only commit locally and push nothing themselves.

### Consequences

- A future agent/ad-hoc session knows to verify driver changes exclusively through the test suites, never by sourcing the driver in a live shell.
- The `bin/` tests remain the single verification seam for driver logic.
- If a driver ever does need interactive probing, the safe pattern is: fixture workspace, guard exported, mock binaries, `--dry-run` (or plain run inside the fixture).

### Revision triggers

- If drivers grow an interactive/REPL mode where sourcing is intended, this rule changes.
- If a driver is ever found to push or mutate the remote on its own (it should not), the recovery story changes and the rule becomes load-bearing.
