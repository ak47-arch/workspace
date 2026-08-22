# PRD Reviewer Agent — Artefact Map

**Why this document exists**: the prd-reviewer is the factory's **readiness gate
before implementation** — the worker that verifies a plan document (PRD) is a
routeable entry point so an implementation agent can pick it up and build
end-to-end with no user interaction. Unlike the implementer/code-reviewer, it is
**not a decoupled host-driver + sandbox pipeline**: it is invoked **in-session**
(`agentScope: project/both`) and performs a read-mostly document check with no
git mutation, no build, and no PR to raise. It therefore has **no** `bin/*-run.sh`
driver, **no** container, and **no** runtime config — that lighter shape is
intentional, not a gap. This map resolves every artefact in one hop.

**Core rule**: the prd-reviewer is **read-only**. It may run read-only git
(`log/show/status`) and read files, but never creates, modifies, or deletes
anything, never runs builds, and never transitions tasks. It returns a structured
**BLOCKING / READY** verdict with blocking + advisory findings.

---

## Build artefacts — source of truth (versioned)

| Artefact | Location |
|---|---|
| Worker persona (brain + checks + output schema) | `.pi/agents/prd-reviewer.md` |
| Worker run contract (this task, invoked in-session) | `.agents/skills/prd-reviewer-ops/SKILL.md` |
| Artefact map (this doc) | `docs/reference/prd-reviewer-agent.md` |
| Roster entry (component staffing, discoverable) | `docs/factory-context.md` |

**Not present — by design (do not "fix")**:
- No host driver `bin/prd-run.sh` — PRD gating is in-session via `agentScope`.
- No sandbox container / config — the gate reads repo docs only; no build needed.
- No test suite — no mutation surface to unit-test.

## Runtime artefacts — what the gate consumes / produces

| Artefact | Location | Direction |
|---|---|---|
| PRD under review (read-only) | `docs/prd/<date>-<slug>.md` | consumed |
| Task file (read-only, consistency vs PRD) | `docs/tasks/<slug>.md` | consumed |
| Task index line (slug uniqueness) | `docs/tasks.txt` | consumed |
| Context engine chain (factory-context, openwiki, decisions, session) | `docs/factory-context.md` · `openwiki/` · `docs/knowledge/` | consumed |
| Verdict report (produced) | posted back to the invoking session / task discussion | produced |

## Boundaries

- Gate ## Steps: **before** implementation. Never the code-reviewer's role
  (post-implementation PR check) or the implementer's (build).
- Never modify any file. Return only the verdict; a PRD that is not ready is
  reported as **BLOCKING** with the blocker list — never silently rewritten by
  the reviewer.