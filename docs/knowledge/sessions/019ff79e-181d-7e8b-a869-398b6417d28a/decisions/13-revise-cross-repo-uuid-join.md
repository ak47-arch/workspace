## Decision: `--revise` supports cross-repo / pre-reviewer-era PRs — requires a 36-char impl-session UUID on the task's `Raised by` row

**Status**: accepted
**Date**: 2026-08-15 01:45
**Task**: [extension-inline-agent](../../../../tasks/extension-inline-agent.md)
**Project**: feed_analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: A pre-reviewer-era (or any hand-raised) task whose Raised by row lacks a 36-char impl-session UUID gets its UUID backfilled on the task file so --revise resolves cleanly.

### Context

`extension-inline-agent` was implemented in the **pre-reviewer era** (Aug 12,
repo `feed_analyser`, original impl session `60c0c537`, task in a *different*
repo than the software-factory workspace). The first factory review
(2026-08-15) returned REQUEST_CHANGES (one blocking US5 `FileNotFoundError`).
Per decision 08 the implementer must fix via `--revise`, but this PR was
**cross-repo** and **pre-reviewer-era** — both untested paths for the revision
**Summary**: ## Decision: --revise supports cross-repo / pre-reviewer-era PRs — requires a 36-char impl-session UUID on the task's Raised by row Status: accepted Date: 2026-08-15 01:4
flow.

### Problem

`--revise` joins PR → task → original impl session by parsing the task's PR
tracking row `Raised by: implementer run <36-char-uuid>` (decision 06). The
pre-reviewer row said `Raised by: implementer run 60c0c537` — an 8-char run
id, **no 36-char UUID**. Consequences:
- `IMPL_UUID` extracted the whole line as garbage.
- The seeded-session lookup failed → **continuity seed skipped** (decision 08
  broken).
- Worse, the container name is `impl-$IMPL_UUID`; the garbage string had spaces
  and parens, which **podman rejects** (`names must match [a-zA-Z0-9][a-zA-Z0-9_.-]*`)
  → every attempt died exit 125 before doing anything.

### Alternatives

- **Hand-fix the PR branch / re-implement.** Rejected — decisions 08/02 say the
  implementer owns its fixes and in-container truth mirrors the host; the
  session continuity is the whole point.
- **Have the driver tolerate a short id.** Rejected — the driver convention is
  a 36-char UUID and downstream (seed filename, container name, knowledge dir)
  all key on it; patching the driver to guess is worse than fixing the data.
- **Add the 36-char UUID to the task's `Raised by` row (chosen).** One-line
  metadata correction: `implementer run 60c0c537-b9c7-4c4c-8b8a-0be438950151`
  (the task's existing impl-session reference, whose `docs/knowledge/sessions/…/`
  transcript is byte-identical to the `~/.factory` native session id `019ff2d7`).
  This makes the existing driver conventions work unchanged.

### Decision

A pre-reviewer-era (or any hand-raised) task whose `Raised by` row lacks a
36-char impl-session UUID gets its UUID **backfilled on the task file** so
`--revise` resolves cleanly. The UUID is the task's existing implementation
session (from the `## Sessions` list), and its `docs/knowledge/sessions/<uuid>/`
transcript must exist (confirmed identical to the native session preserved in
`~/.factory/runs/{slug}-{ts}/sessions/`). `--revise` then seeds `--continue`
continuity and the valid container name become `impl-<uuid>`.

### Rationale

Keeps decision-08 continuity intact without re-implementing; the coordinate that
was missing was data (a UUID on the join key), not behavior. Also confirmed pi's
`--continue` loads the newest seeded `.jsonl` regardless of filename vs internal
id mismatch (the ponytail case used filename `8483b243` with internal id
`01a000fb`), so the seed filename convention need not match the transcript's own
id.

### Consequences

- `--revise` now works for cross-repo (`feed_analyser#1`) and pre-reviewer-era
  PRs: original session resumed, line-for-line fix applied, revision 1 pushed to
  the same branch, re-review → APPROVE, merged via `merge-pr.sh`.
- The join invariant is now explicit: **every task's `Raised by` row must carry
  a 36-char UUID** for `--revise` to target it.
- Backfilling a UUID is a data correction on the task file (workspace commit;
  library hygiene), not a driver change.

### Revision triggers

- A gh/`--revise` change that relaxes the UUID requirement to a short id would
  make backfill unnecessary — prefer the data fix only while the convention
  stands.
- pi changes `--continue` to require filename==internal id — then the seed
  filename in `prepare_revision_dir` must be reconciled (currently it trusts the
  latest `.jsonl` in the dir).
- A future pre-reviewer-era task is merged without ever being revised — backfill
  guidance is moot but the invariant on new tasks stays.
