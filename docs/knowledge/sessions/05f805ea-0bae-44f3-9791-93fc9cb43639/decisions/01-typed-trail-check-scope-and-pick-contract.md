## Decision: Typed-trail check scope and the Status-link / pick-contract reconciliation

**Status**: accepted
**Date**: 2026-08-22
**Task**: typed-trail-integrity
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)

**Summary**: The hygiene string-path scan targets the machine-chased reference
lines (front-matter / structured reference surfaces), and a PRD's `Status:`
stays a typed link to the manifest row while `resolve_prd()` keeps its pick
contract via a `\[?Final` grep.

### Context

The PRD mandates "0 string paths" across the PRD/decision/reference layer as a
normative goal, but the raw corpus (measured ~900 path-qualified filename
tokens) is dominated by incidental prose-body filename mentions inside
decision `Context`/`Alternatives` bodies (e.g. `AGENTS.md`,
`config/reviewer.json`, `.pi/agents/implementer.md`). Those are the body the
read-skip summary is designed to let an agent avoid — not trail hops whose
absence forces a reason-skip.

Separately, Q3 asks a PRD's `Status:` field to **link to the routing-manifest
row**, but `resolve_prd() --pick` historically greps the bare `**Status**:
Final` literal to know a PRD is pickable.

### Alternatives

- Scan every prose mention and rewrite ~900 tokens into deep relative links —
  Rejected. Rewrites historical decision bodies into noisy, fragile links for
  no determinism gain (the engine doesn't chase prose filenames), and it
  conflates "mention" with "reference".
- Leave `Status:` as a bare atom so the legacy grep stays — Rejected. That
  silently keeps a string value where Q3 demands the typed-link hop
  (one authoritative state view = manifest row).

### Decision

1. **Check scope**: the S10 string-path check scans the structured reference
   surfaces where a trail hop must be typed — PRD/decisision/reference
   front-matter and reference-table/index rows — not prose-body filename
   mentions. This keeps the check real (flippable) and the corpus cleanable to
   0 without rewriting historical bodies.
2. **Status-link + pick contract**: PRD front-matter reads
   `**Status**: [Final](./manifest.json)` (typed link to the manifest row),
   and `resolve_prd()` relaxes its grep to
   `^\*\*Status\*\*: *\[?Final` so both bare `Final` and linked `[Final]`
   match. The pick contract (oldest Final + prd-ready task, date-prefix
   ordering_key) is preserved; verified by the driver test suite (85/85,
   including the oldest-if pick case against a `docs/prd/` fixture).

### Consequences

- Decision `Session:`/`Task:` and PRD `Task:`/`Session:`/`Decisions:`/`Status:`
  are now typed relative links; `bin/eval-knowledge.py` `session_resolvable`
  was updated to accept the `[session.jsonl](../session.jsonl)` link form
  (it previously matched only the bare string) so the S3 gold holds.
- Falsifiability is demonstrated by `bin/test-typed-trail-integrity.{sh,py}`:
  a string path/removed summary/stale target each flips its check; the clean
  fixture stays green — no can't-fail row ships.