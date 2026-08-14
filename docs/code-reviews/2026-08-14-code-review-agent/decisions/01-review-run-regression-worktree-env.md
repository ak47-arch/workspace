# Decision: review-run regression gate is a full-workspace check (manifest-branch env limitation)

- Slug: code-review-agent · Review session: 50a4071f-d405-43eb-a123-dc4e64e02974
- Date: 2026-08-14
- Status: adopted (advisory observation from review, recorded for future review runs)

## Context

While verifying the PRD's regression criterion ("existing implementer driver suite +
transition suite still pass") inside the read-only PR-head worktree, the implementer
driver suite (`bin/test-implementer-driver.sh`) reported `28 pass / 1 fail`:
`resolve_repo MANIFEST_BRANCH = 'master' — expected public-release`.

## Decision

Treat that single failure as **environmental, not a regression of this PR**. The failing
lookup lives in `implementer-run.sh`'s `resolve_repo` and the shared
`workspace_restore_manifest.json` — neither is touched by this PR (its only edit to
`implementer-run.sh` is the `factory:needs-review` label block). Root cause:
`workspace-portability/` is gitignored from the sandbox worktree clone, so the fixture's
manifest `cp` fails silently and the manifest-branch lookup falls back to `master`. A
direct reproduction of the same lookup against the real host `/workspace` manifest
(which contains `feed_analyser → public-release`) returns the expected value.

## Consequence

- The review-worker's in-container sandbox (PR head checkout) cannot fully run
  `test-implementer-driver.sh` as a clean regression gate; it should be re-run in the
  full host workspace (where `workspace-portability/` exists) before relying on the
  "implementer suite still passes" claim.
- This does not affect the new `test-review-driver.sh` (50/50) or
  `test-transition-task.sh` (45/45).
- Declared here so future review runs don't rediscover or misattribute the failure.
