**Summary**: ## Decision: Label seam — gh pr edit --add-label fails on this gh (classic-Projects GraphQL error); use the REST labels API - Slug: code-review-agent · Review session: 19

**Summary**: Use the REST issue-labels endpoints in update_label() (bypass projectCards)

## Decision: Label seam — `gh pr edit --add-label` fails on this gh (classic-Projects GraphQL error); use the REST labels API

- Slug: code-review-agent · Review session: 19cb853b-a2e9-4eb6-865a-138864ba1934
- Date: 2026-08-14
- Status: accepted (found during UAT hand-off of the first dogfood review)

### Context

The first dogfood run printed `Labeled ak47-arch/workspace#1 → factory:reviewed-ok.`
but the PR showed **no labels**. `gh label create --force` succeeded
(`factory:reviewed-ok` existed), yet `gh pr edit --add-label/--remove-label` exited 1:

```
GraphQL: Projects (classic) is being deprecated in favor of the new Projects
experience ... (repository.pullRequest.projectCards)
```

A known upstream gh quirk: `gh pr edit`'s GraphQL mutation touches
`projectCards`, which errors for accounts/repos where classic Projects is
deprecated. The driver swallowed it with `|| true`, so "Labeled" was false.

### Decision

Use the **REST issue-labels endpoints** in `update_label()` (bypass projectCards):

- add: `gh api -X POST repos/<o>/<r>/issues/<n>/labels -f labels[]=factory:<outcome>`
- remove: `gh api -X DELETE repos/<o>/<r>/issues/<n>/labels/factory:needs-review --silent`

Verified working on this repo (add + delete round-trip, exit 0). Also: the mock
`gh` in `test-review-driver.sh` now **rejects `pr edit` loudly** (exit 1) so any
stale caller fails tests instead of silently no-op-ing, and gains an `api` case.

### Rationale

The label is the `--pick` seam's trigger — a silently-failed label would strand
`--pick` and the whole reviewed/needs-review routing. REST is stable, call-logged,
and testable with the mock.

### Consequences

- `factory:needs-review` + `factory:reviewed-ok` exist on the repo (created with
  `gh label create --force`, idempotent).
- The implementer's `gh pr create --label factory:needs-review` uses the *create*
  mutation (different path than `pr edit`); verification on the next real
  implementer PR remains a UAT item.

### Revision triggers

- gh upstream fixes `pr edit` projectCards → could revert, but REST is simpler and
  stable; no plan to revert.
