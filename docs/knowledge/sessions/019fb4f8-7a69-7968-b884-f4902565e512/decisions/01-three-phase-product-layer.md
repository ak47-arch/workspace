## Decision: Three-Phase Product Layer with Vertical Slicing as Guiding Principle

**Status**: accepted
**Date**: 2026-07-31 23:57
**Task**: extend-software-factory-wsff
**Project**: software-factory
**Session**: sessions/019fb4f8-7a69-7968-b884-f4902565e512/session.jsonl

### Context

The product/architecture layer of the software factory had a single phase: grill → PRD → capture decisions. The wsff.md article ("Why Software Factories Fail") proposed a 4-phase planning model — Product Design → System Architecture → Program Design → Vertical Slices — and argued that front-loading alignment reduces rework and review time when working with AI coding agents.

### Problem

The existing product layer produced a PRD and then handed off to the assembly line without intermediate structural analysis. For medium-to-large tasks, this meant the implementation agent had to infer system structure, module boundaries, and type design from the PRD alone — leading to the quality degradation patterns described in the article (shotgun surgery, try-catch-wrapped everything, lazy type casts).

### Alternatives

- **Adopt all 4 phases as formal artifacts** — Rejected. Vertical Slices is a delivery principle, not a document phase. The article's author says "most frontier models won't design a plan like this without human steering" and "I prefer to stay in the loop here" — trying to formalise it into a rigid handoff would over-constrain the implementation agent and add ceremony without proven benefit.

- **Keep the single-phase approach (PRD only)** — Deferred. Works for Small tasks but insufficient for Medium and Large tasks. The article's evidence that models degrade codebase quality over time makes a strong case for adding structural analysis phases.

- **Add all phases as separate files** — Rejected. The user explicitly stated that separate files increase clutter. A single document per task with accumulating sections is preferred.

### Decision

The product/architecture layer adopts a **three-phase analysis model** with **one guiding principle**:

**Phases** (sequential, applied based on task category):
1. **Product Design** — produces the PRD (problem, solution, user stories, decisions)
2. **System Architecture** — sequence diagrams, endpoint contracts, data model shapes
3. **Program Design** — call-stack trees, file-tree diffs, key types and signatures

**Guiding principle** (not a phase, not an artifact):
- **Vertical Slicing** — the principle that end-to-end slices are preferred over horizontal stack-order plans. The implementation agent receives this as an open-ended requirement in the PRD and determines how to apply it per-task.

**Task categorisation** gates which phases run:
| Category | Criteria | Phases |
|----------|----------|--------|
| Trivial | Single file, no new logic | None — implement directly |
| Small | 1-3 files, existing seam | Product Design only |
| Medium | Crosses modules, 3+ files | Product Design + System Architecture |
| Large | New service/project, major refactor | All three phases |

All phases produce content into a **single document** (the task's plan file, which starts as the PRD and accumulates sections). No separate files per phase.

### Rationale

- The three analysis phases address the specific failure mode the article identifies: models making poor structural decisions when given only functional requirements.
- Keeping Vertical Slicing as a principle rather than a phase avoids over-engineering the handoff. The article itself warns against rigidifying this step.
- Single-file accumulation per task keeps the filesystem navigable and traceability tight — one grep for `Task: <slug>` finds everything.
- Task categorisation follows the 80/20 rule from the article: not every task needs full ceremony, and the category is set at pickup time based on explicit criteria.

### Consequences

- The product-layer skill (product-layer/SKILL.md) will need updating to reflect the three-phase model and task categorisation.
- Medium and Large tasks will produce longer plan documents with Architecture and Program Design sections.
- The assembly line's context will need to include the Vertical Slicing principle so implementation agents understand the preference for end-to-end slices.
- The task file's lifecycle states remain unchanged (`in-prd → prd-ready → in-implementation → in-verification → complete`) — the phases all happen within `in-prd`.

### Revision triggers

- If real usage data shows that the three-phase model adds ceremony without measurable quality improvement for Medium/Large tasks.
- If models improve to the point where structural decisions no longer need human pre-validation (i.e., the article's core thesis becomes outdated).
- If the single-file approach becomes unwieldy for very Large tasks (e.g., >50 pages).