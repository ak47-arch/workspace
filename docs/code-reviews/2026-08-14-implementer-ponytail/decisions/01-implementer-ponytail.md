# Decision: committed `opensource` symlink is out-of-scope — must be dropped from the commit

**Status**: review-emerged (advisory, blocking for this PR)
**Date**: 2026-08-14
**Task**: implementer-ponytail
**Review session**: 5b63c492-0880-4411-8ff5-26575091edff

## Context

The PR diff `base...head` (`86363fd..212370c`) contains a new tracked symlink
`opensource -> /workspace/opensource` (`new file mode 120000`). This artifact:

- is **not** in the PRD file map (PRD lists only `config/implementer.json`,
  `bin/implementer-run.sh`, `.pi/agents/implementer.md`,
  `bin/test-implementer-driver.sh`, plus bookkeeping);
- contradicts the implementer's own decision record
  `docs/implementations/2026-08-14-implementer-ponytail/decisions/01-implementer-ponytail-test-env.md`,
  which explicitly states the symlink is "gitignored via `opensource/`" and
  "never enter[s] the commit" and "the commit contains only the four real
  source files";
- is unused by every code path in the diff — the driver, config, and tests all
  use the absolute `/workspace/opensource/ponytail/skills` path;
- is a dangling absolute-host-path symlink on any non-host clone / CI.

## Root cause

The env-bootstrap intent (make the bare-worktree suite self-contained by
symlinking the gitignored host `opensource` dir) failed silently: the `.gitignore`
pattern `opensource/` (line 59, directory-only) does **not** match a symlink
(file mode 120000). `git check-ignore opensource` returns non-zero, so the symlink
was added to the commit instead of remaining untracked.

## Decision

Before merge, amend the PR head so the commit contains only the four
PRD-mapped source files (drop the `opensource` symlink). If the untracked
env-bootstrap symlink is still wanted for the bare-worktree sweep, extend
`.gitignore` to match the symlink itself (e.g. `opensource` or `opensource*`),
keeping it untracked as originally intended. Do not rely on the directory-only
`opensource/` pattern to exclude a symlink.

## Consequences

- Clean, PRD-scoped diff; no broken absolute-path artifact in the repo.
- Review-driver Test 7 (`opensource/ponytail/skills/...` exists at checkout root)
  still requires a live `opensource` at the checkout on a real host; the driver's
  flags use the absolute `/workspace/opensource` path regardless.

## Revision triggers

- If any code path begins resolving skills via the repo-root `opensource`
  relative path, revisit (but that would contradict the absolute-path config
  precedent in `review-run.sh` / decision 04).
- If `.gitignore` is changed to stop excluding `workspace-portability/` or the
  `opensource` bootstrap, the untracked artifacts would re-enter commits.
