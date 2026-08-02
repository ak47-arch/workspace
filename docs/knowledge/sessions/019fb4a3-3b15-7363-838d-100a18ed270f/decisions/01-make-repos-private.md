## Decision: Make feed_analyser and goal-agent (survival-infrastructure) Private

**Status**: accepted
**Date**: 2026-07-31 01:56
**Task**: feed-analyser-survival-infra-private-repos
**Project**: workspace-portability
**Session**: sessions/019fb4a3-3b15-7363-838d-100a18ed270f/session.jsonl

### Context

The workspace contains two first-party projects — `feed_analyser` and `survival-infrastructure` (hosted on GitHub as `goal-agent`) — that were publicly visible. As the software factory evolves toward production use, these repos contain personal data, API keys in commit history, and architecture decisions that should not be publicly discoverable.

### Problem

Public repos expose sensitive intellectual property and personal data. The workspace-portability system relies on `GITHUB_TOKEN`-authenticated cloning, so making repos private doesn't break restore — but the change must be coordinated across the manifest and documentation.

### Alternatives

- **Create new private repos and migrate**: More work, risks losing git history and GitHub Issues/PRs. Not needed when the existing repos can simply be toggled to private.
- **Leave public**: No longer appropriate as the workspace contains personal infrastructure data.
- **Delete and recreate**: Destructive and unnecessary.

### Decision

Use `gh repo edit --visibility private` to flip both `ak47-arch/feed_analyser` and `ak47-arch/goal-agent` from PUBLIC to PRIVATE on GitHub. No new repos are created, no URLs change, and the existing clone URLs in the workspace-portability manifest remain valid (they just require authentication now).

### Rationale

- Minimal change — one command per repo, no data migration.
- The workspace-portability system already authenticates via `GITHUB_TOKEN` for all clone operations, so private repos work identically to public ones.
- No manifest changes needed — clone URLs are the same for public and private repos on GitHub.
- Preserves full git history, Issues, PRs, and GitHub configurations.

### Consequences

- `feed_analyser` and `goal-agent` are no longer publicly accessible or discoverable.
- Anyone who previously cloned the public repos can still access their local copies, but can no longer fetch/pull without authentication.
- The workspace-portability restore system continues to work unchanged — auth is already handled.
- `docs/projects.md` and the manifest reference the same URLs; no doc updates needed.

### Revision triggers

- If the repos are later made public again (e.g., for open-sourcing parts of the project).
- If the workspace-portability system changes its auth strategy (e.g., drops `GITHUB_TOKEN` support).
- If the repos are renamed or migrated to a different GitHub account.