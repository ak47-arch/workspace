# Decision: Delivery-failure test injects a mock `gh` via PATH (not the gh_call seam)

- **Status**: accepted (advisory — recorded during code review, no rework required)
- **Date**: 2026-08-17
- **Task**: implementer-delivery-failure-loud
- **Review session**: f28bb390-3980-46cd-956b-c3bcf33d9d4b

## Context

The implementer's recorded decision D01 (`docs/implementations/2026-08-17-implementer-delivery-failure-loud/decisions/01-delivery-failure-loud-gh-seam.md`) and the archived report both state that `push_and_pr()` routes delivery `gh` calls through the `gh_call()`/`IMPLEMENTER_GH_BIN` seam. The actual final code (`bin/implementer-run.sh`) leaves raw `gh` calls in `push_and_pr` (`command -v gh`, `gh label create`, `gh pr create`). The failing-PR delivery test (`bin/test-implementer-driver.sh` `write_mock_gh`) instead injects a mock `gh` on `PATH` (`PATH="$DELIV:$PATH"` with a `$DELIV/gh` that exits 1 for `pr`).

## Decision

Accept the review verdict (APPROVE) with this divergence noted as advisory. The observable behavior required by PRD US2 — a failing `gh pr create` is detected and routed to `fail_run` (exit 1, FAILED reason, task reverted to prd-ready, branch left on remote) — is genuinely implemented and genuinely tested. The PATH-injection approach is functionally equivalent to the D01 seam approach for real runs (real `gh` on PATH is the real binary) and satisfies the PRD's "Add a failing-`gh pr create` mock" requirement.

## Consequence

- No correctness/scope/decision-blocking finding; verdict APPROVE.
- Action item for the next iteration: update `decisions/01-delivery-failure-loud-gh-seam.md` and `report.md` to describe the PATH-injection mock actually used (or apply the D01 seam if it is preferred) so the archived decision/report match the code.
