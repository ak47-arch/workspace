# Decision: restore the "say no to vanishing scope" binding rule to the implementer persona

**Status**: review-emerged (blocking for this PR)
**Date**: 2026-08-14
**Task**: implementer-ponytail
**Review session**: 85f5ce0b-7de4-4230-9f17-151742cac9b9
**Related**: PRD US4 + implementation decision D5; `.pi/agents/implementer.md`

## Context

PRD US4 requires the rewritten ponytail section to reference the loaded skills
while KEEPING every factory-specific binding rule — explicitly enumerated as
"no git — the host owns it; verify what you build; respect the brief/outbox; say
no to vanishing scope" — and its done-condition is "every factory binding rule
still appears". Decision D5 likewise states the factory rules "stay in the persona".

The diff at head `20c84ac` rewrote the working-style section to load the six real
skills, but:
- "say no to vanishing scope" is absent from `.pi/agents/implementer.md` AND
  `.agents/skills/implementer-ops/SKILL.md` (grep for `vanish`/`unresolv`/
  `ambiguous` finds nothing);
- "verify what you build" is no longer a binding-rule bullet — only an
  ops-contract "run verification" mention (implementer.md line 73) survives.

## Problem

The revision-1 report claims "US4 — PASS ... all five binding rules retained
(5/5)", which measures the wrong set and is inaccurate for the US4-enumerated
rules. The implementer's behavioral guardrail for ambiguous stories (implement
the deterministic best interpretation and hand it off to UAT) is lost.

## Decision

Before merge, restore "say no to vanishing scope" (and re-affirm "verify what
you build") as explicit binding-rule bullets in `.pi/agents/implementer.md`, so
US4's done-condition is met. Optionally mirror "vanishing scope" in the
`implementer-ops` run contract for redundancy.

## Consequences

- Implementer retains its ambiguity-handling guardrail across runs.
- US4 / D5 conformance restored; revision-1 report's US4 claim becomes accurate.

## Revision triggers

- If the factory intentionally replaces the vanishing-scope rule with a
  different mechanism, revisit and record that decision explicitly.
