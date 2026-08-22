## Decision: restore the "say no to vanishing scope" and "verify what you build" binding rules to the implementer persona

**Status**: accepted
**Date**: 2026-08-14
**Task**: [implementer-ponytail](../../../../tasks/implementer-ponytail.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Chosen alternative 2.

### Context

PRD US4 requires the rewritten ponytail working-style section to reference the
loaded skills while KEEPING every factory binding rule ("no git — the host owns
it; verify what you build; respect the brief/outbox; say no to vanishing scope"),
with the done-condition "every factory binding rule still appears". Decision D5
requires "vanishing scope stays in the persona".

The review (authoritative, `/sandbox/review/report.md` +
`/sandbox/review/decisions/01-implementer-ponytail-vanishing-scope.md`) found the
revision-1 persona dropped "say no to vanishing scope" from both
`.pi/agents/implementer.md` and `.agents/skills/implementer-ops/SKILL.md`, and
demoted "verify what you build" from a binding-rule bullet to an ops-contract
mention.

### Problem

The implementer's ambiguity-handling guardrail (implement the deterministic best
interpretation and hand it off to UAT) was lost, and US4 / D5 conformance was
broken. The revision-1 report's "US4 — PASS (5/5 binding rules)" claim measured
the wrong rule set.

### Alternatives

1. Restore both rules only in the persona (the review's mandatory fix).
2. Restore both rules in the persona **and** mirror them in the
   `implementer-ops` run contract (the review decision explicitly sanctions this
   "for redundancy", and the blocking finding names both files).
3. Do nothing / argue the ops-contract reference implies the rules — rejected: the
   review's binding finding and decision override prior reasoning.

### Decision

Chosen alternative 2. In `.pi/agents/implementer.md`, re-added "verify what you
build" and "say no to vanishing scope" as explicit binding-rule bullets (rules 6
and 7) in the "Factory-worker rules (binding)" section. In
`.agents/skills/implementer-ops/SKILL.md`, mirrored both rules in the "## 4. Hard
rules (non-negotiable)" section for redundancy.

### Rationale

- Directly satisfies the review's blocking finding and US4's done-condition /
  decision D5.
- The blocking finding names both files as having dropped the rule, so the ops
  mirror is fixing a stated finding, not scope expansion.
- Restoring the exact original wording preserves the guardrail's intent.

### Consequences

- The implementer retains its ambiguity-handling guardrail across runs.
- US4 / D5 conformance restored; the report's US4 claim is now accurate.
- Two source files modified this revision; no behavior in the driver/tests changed
  (tests do not read the persona), so the test suites are unaffected.

### Revision triggers

- If the factory intentionally replaces the vanishing-scope rule with a different
  mechanism, revisit and record that decision explicitly.
