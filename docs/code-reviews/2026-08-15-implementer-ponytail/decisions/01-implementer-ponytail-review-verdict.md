# Review decision — implementer-ponytail

- **Status**: accepted
- **Date**: 2026-08-14
- **Task**: implementer-ponytail
- **Project**: software-factory
- **Session**: 6b560fbb-bfe9-450b-94f9-fb24d8dadcec
- **PR**: ak47-arch/workspace#2

## 01-implementer-ponytail-review-verdict.md

### Context

Review of PR #2 (head `2e4a946` vs base `86363fd`) against
`docs/prd-queue/2026-08-14-implementer-ponytail.md`.

### Decision

**APPROVE.** All five user stories implemented and evidenced. Every PRD
acceptance check passed in-sandbox except two documented **pre-existing,
environmental** suite failures that cannot pass in a bare checkout:

- `test-implementer-driver` MANIFEST_BRANCH (needs the gitignored
  `workspace-portability/workspace_restore_manifest.json`, absent here) — 33/34;
- `test-review-driver` skills-dir check (needs the live `opensource/` checkout at
  repo root) — 60/61; review files are out-of-scope for this PR.

Both are byte-identical at base (verified via `git show`), and both are expected
to pass on a real host (decision 01 of the implementation session documents the
acceptance of these environmental failures). The PR's own six new ponytail
assertions all pass, `test-factory-run` (22), `test-merge-pr` (8), and
`test-transition-task` (45) are all green.

The review's previous blocking findings from revision 1 are resolved: the
out-of-scope committed `opensource` symlink is removed from the head tree
(verified via `git ls-tree`), `.gitignore` now matches a bare `opensource`
symlink (decision `01-implementer-ponytail-test-env`), and the persona restores
the "verify what you build" + "say no to vanishing scope" binding rules (US4).

### Rationale

- The diff honors D1 (mirror `review-run.sh` exactly) — identical skill names,
  seam shape, config keys/fallbacks, env line, and injection position.
- D2 (live read-only checkout, no vendoring), D3 (`IMPLEMENTER_PODMAN_BIN` seam,
  `exec` dropped for the function seam), D4 (ultra mode), D5 (binding rules in
  persona) all confirmed.
- Scope is clean: six changed files all within the PRD file map or review/decision
  sanctioned extras (`.gitignore`, `implementer-ops` SKILL.md redundancy mirror).
- No blocking findings, no open ponytail debt.

### Consequences

- UAT items are limited to re-running the two environmental suites on a real
  host, confirming the jq path, and confirming a real container `pi` invocation
  (no podman in this sandbox).
