## Decision: Workflow-file pushes need `workflow` scope; use GH_TOKEN + git insteadOf, not `gh auth login`

**Status**: accepted
**Date**: 2026-08-17 17:27
**Task**: [headless-agent-containerisation](../../../../tasks/headless-agent-containerisation.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Two patterns, now baked into factory.yml: 1.

### Context

2026-08-17: the implementer produced `.github/workflows/factory.yml`; the host's
branch push was rejected — *"refusing to allow an OAuth App to create or update
workflow … without `workflow` scope"*. The local token (`gho_…`, scopes
`gist, read:org, repo`) lacked the scope. After a one-time device-flow grant
(`gh auth refresh -h github.com -s workflow`), the push worked. In CI, the first
smoke test then failed at `gh auth login --with-token`: *"missing required scope
'read:org'"*.

### Problem

GitHub deliberately gates `.github/workflows/*` mutations behind the `workflow`
scope, and `gh auth login --with-token` additionally demands `read:org` on
classic tokens — friction that blocked both local delivery and the CI job.

### Alternatives

- **Add `read:org` to the classic PAT** — works, but broadens the CI identity
  and requires browser regeneration of the token.
- **Fine-grained PAT with Workflows permission** — viable (offered to the user);
  user chose classic with the workflow-scope grant.

### Decision

Two patterns, now baked into `factory.yml`:
1. **CI auth**: set `GH_TOKEN: ${{ secrets.FACTORY_GH_PAT }}` at job level (gh
   CLI reads it directly, no login, no validation) and teach git the token via
   `git config --global url."https://x-access-token:${FACTORY_GH_PAT}@github.com/".insteadOf "https://github.com/"`.
   Do NOT use `gh auth login --with-token` (demands `read:org`).
2. **Local auth**: one-time `gh auth refresh -h github.com -s workflow` grants
   the scope to the existing token; the grant is per-token, not per-run.

### Rationale

Keeps the CI credential least-privileged (no `read:org` needed), avoids gh's
login validation entirely, and the `insteadOf` rewrite covers both repo_map
clones and driver pushes with zero gh dependency.

### Consequences

- Local tokens and PATs that touch workflow files need the `workflow` scope
  (or a fine-grained equivalent) once per token.
- CI jobs authenticate via `GH_TOKEN` + git URL rewrite — no interactive auth
  ever appears in runs.
- New machines/tokens need their own one-time grant.

### Revision triggers

- GitHub changes the OAuth-workflow-scope or `read:org` validation behavior.
- Fine-grained PATs become the chosen CI credential (different permission
  surface; `Workflows: read/write` replaces the classic `workflow` scope).
