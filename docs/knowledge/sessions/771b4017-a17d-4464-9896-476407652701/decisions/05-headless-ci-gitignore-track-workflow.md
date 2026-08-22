**Summary**: # Decision 05 — headless CI must track the root .github/ workflow - Date: 2026-08-17 - Session: 771b4017-a17d-4464-9896-476407652701 (implementer, headless-agent-containe

**Summary**: Summary: # Decision 05 — headless CI must track the root .github/ workflow - Date: 2026-08-17 - Session: 771b4017-a17d-4464-9896-476407652701 (implementer, headless-agent

# Decision 05 — headless CI must track the root `.github/` workflow

- **Date**: 2026-08-17
- **Session**: 771b4017-a17d-4464-9896-476407652701 (implementer, headless-agent-containerisation)
- **Status**: Accepted

## Context

The PRD requires a new workflow `.github/workflows/factory.yml` on the root
workspace repo. The repo's `.gitignore` contains `/.github/`, which blanket-ignores
the entire directory. Without a change, the host's `git add` would silently drop
the workflow and story 1 (CI auto-starts on a Final PRD push) could never fire.

## Options considered

- **Leave `.gitignore` untouched**: the workflow would not be committed; story 1
  cannot work. Rejected.
- **Narrow negation** (`!.github/` + `.github/workflows/` + `!.github/workflows/factory.yml`):
  git ignore rules cannot re-include a file inside an excluded parent
  ("It is not possible to re-include a file if a parent directory of that file
  is excluded"), so `factory.yml` stayed ignored. Rejected.
- **Un-ignore the directory** (`/.github/` then `!.github/`): makes the whole
  root `.github/` trackable; simple and works. Accepted.

## Decision

Negate the root `.github/` directory in `.gitignore` so the factory workflow is
trackable/committable:

```gitignore
/.github/
!.github/
```

## Consequences

- `.github/workflows/factory.yml` is trackable and will be committed by the host.
- Any other file placed under root `.github/` would also be trackable. The
  workspace root currently holds no other workflows; if per-project workflows
  must be excluded later, a `.github/workflows/` re-exclusion is not achievable
  via ignore negation (git limitation) and would need a different mechanism.
