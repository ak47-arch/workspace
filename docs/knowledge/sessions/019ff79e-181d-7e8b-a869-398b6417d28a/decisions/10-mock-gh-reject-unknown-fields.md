## Decision: Mock gh must reject unknown `pr view --json` fields — host-gh compatibility is a live seam

**Status**: accepted
**Date**: 2026-08-15 01:10
**Task**: software-factory
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: In bin/implementer-run.sh pr_revision_metadata(): drop merged from the gh pr view --json list.

### Context

The first real `--revise 2` run (decision 08's payoff) died on the host at
`pr_revision_metadata()` with "gh could not fetch PR ... (is gh authenticated?)".
The driver requests `gh pr view --json number,...,state,merged`, but **`merged`
is not a valid `--json` field in gh 2.45.0** — the whole command errors and
returns empty JSON. This is the same family as the `baseRefOid` host bug the
code-review dogfood caught earlier (decision 02's simulation blind-spot).

### Problem

The in-container mock gh answered any requested field with fixed fixture JSON,
so the 48/1 suite was green while the real host gh could no more serve `merged`
than `baseRefOid`. The add/verify suite (mock-based) could never catch a driver
requesting a field real gh lacks, because the mock silently *accepted* every
field list.

### Alternatives

- **Switch the driver to `gh api` for PR metadata.** Valid, but a broader refactor
  of `pr_revision_metadata`; not needed to fix the bug.
- **Only drop the `merged` field** (minimal). Fixes the immediate failure but
  leaves the blind spot open — the next invalid field (e.g. `reviewDecision`)
  would recur silently.
- **Make the mock reject unknown `--json` fields (chosen).** The mock `view`
  case now whitelists the fields the driver genuinely uses
  (`number,title,headRefName,baseRefName,headRefOid,state`) and exits 1 with a
  loud "Unknown JSON field" on anything else — so the suite fails if a future
  driver requests a field real gh lacks.

### Decision

- In `bin/implementer-run.sh` `pr_revision_metadata()`: drop `merged` from the
  `gh pr view --json` list. Merged PRs report `state=MERGED`, so guard on
  `$PR_STATE != "OPEN"` (covers merged + closed) with no extra field.
- In `bin/test-implementer-driver.sh` `make_mock_gh_impl()`: the `view` case
  validates the requested `--json` field list against the real gh 2.45 set and
  exits 1 on an unsupported field. Regression net now catches this bug class
  deterministically in-container (suite 53/53 after fix).

### Rationale

Mirrors the baseRefOid mitigation (loud mock instead of lenient mock) and keeps
host-gh field compatibility as an enforced seam rather than an implicit
assumption. Minimal, targeted, no API refactor.

### Consequences

- `--revise <pr>` works against real gh again; merged-PR rejection still correct
  via `state`.
- The mock is now stricter — any current or future driver field list is checked
  by the fixture suite.
- When the factory upgrades gh, the whitelist in the mock (and this entry) is the
  place to update.

### Revision triggers

- A gh release adds/removes `pr view --json` fields — update the mock whitelist.
- The driver switches to `gh api` for PR metadata — the whitelist may become
  moot.
- A new "blind spot" is found that a lenient mock style would hide — generalize
  this to all mock seams (podman arg validation too).
