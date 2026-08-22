## Decision: Organize the implementer as a pointer map, not a physical bundle — agents as a workforce roster

**Status**: accepted
**Date**: 2026-08-12 05:20
**Task**: [implementer-agent](../../../../tasks/implementer-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: 1.

### Context

The implementer system is deliberately spread across three containment models:
factory monorepo conventions (`bin/`, `config/`, `docs/`), pi hosting
conventions (`.pi/agents/`, `.agents/skills/`), and a separate product repo
(`workspace-portability` — the image). After a live run surfaced brittleness
and ~628 MB of per-run dependency/lifecycle bloat, there was pressure to "bundle
the implementer better" — i.e. physically consolidate it under a single folder
(often imagined as a rigid `assembly-line/` tree).

### Problem

Physical bundling treats a human aesthetic as a structural requirement. Agents
do not care how files are arranged; they care about being able to resolve any
artefact in one hop. Worse, physically collapsing build artefacts (source,
image), runtime artefacts, the worker's persona/skills, and config into one
directory (a) breaks the clean build/runtime ownership separation already in
place, (b) turns the abstract `assembly_line` concept into a rigid anks that is
harder to extend, and (c) would force a high-blast-radius migration (paths in
config, persona hosting, portability build dependency, knowledge references)
for zero agent-facing benefit.

### Alternatives

- **Consolidate into a physical `assembly-line/` folder (or dedicated repo).**
  Rejected: high migration risk, couples build+runtime+persona into one blob,
  and over-engineers what is mostly a shell driver into a "platform".
- **Leave things undocumented and hope agents grep.** Rejected: this is exactly
  the inefficient discovery the context-engine layer exists to eliminate.
- **Keep the current layout, add a navigation map (chosen).** The repository
  stays as-is; a single curated pointer document makes every artefact
  resolvable in one hop, with no file moves.

### Decision

1. **Build vs runtime separation stays** — it is intentional and correct.
   Source/image/persona/config live in versioned build locations; the container,
   installed deps, and raw logs are disposable; only outbox + evidence + commit
   are durable.
2. **Do not physically bundle.** Keep `assembly_line` as an abstraction; do not
   create a rigid aggregate folder.
3. **Add a pointer map**: `docs/reference/implementer-agent.md` enumerates every
   build/runtime/config/persona artefact, where it lives, invocation, and the
   invariants (no-git, no-secrets, native session continuation, git-identity).
4. **Wire it into the context engine**: `docs/factory-context.md` points to it
   from the `assembly_line` description and from the `## Pointers` index, so
   agents resolve an artefact in one hop instead of grepping.
5. **Agents are a workforce roster**: a new `## Agents (the workforce)` table in
   `factory-context.md` lists each agent as an employee at its SDLC stage (name,
   stage, role, where it lives / how it runs), with `.pi/agents/<name>.md` as the
   per-agent source of truth and a documented ritual for adding the next hire.

### Rationale

This is the essence of the factory's context-engine backbone: progressive
disclosure via a small, curated navigation layer instead of expensive,
repetitive discovery. A pointer map and a roster give agents (and the user) a
stable, token-cheap way to know "what exists and where" while the underlying
files keep their natural ownership homes. It decouples understanding from
location, so future re-homing never requires agents to re-learn the system.

### Consequences

- No migration: nothing moved, no path churn, no history split.
- `docs/reference/implementer-agent.md` is the canonical implementer artefact
  map; `factory-context.md` (assembly_line note + Pointers index) makes it
  reachable; `AGENTS.md` carries a one-line roster mirror for the cheapest read.
- The dependency/space issue is reframed as a durable-vs-disposable ownership
  rule (spec-level), not a one-off cleanup task.
- Future SDLC stages are staffed by adding a roster row + `.pi/agents/` file,
  keeping the workforce discoverable and the abstraction unrigid.

### Revision triggers

- If a second `assembly_line` component appears and a real, demonstrable
  management burden (versioning/CI conflict) shows up, consider promoting the
  map's subject to a dedicated repo — but only on evidence, not aesthetics.
- If `AGENTS.md`, `factory-context.md`, and `docs/reference/implementer-agent.md`
  drift out of sync (new artefact added but not mapped), the pointer map loses
  its value — re-run the "is every artefact mapped?" check.
- If pi changes how personas/skills are hosted, the persona/skill rows in the
  map must be re-verified.
