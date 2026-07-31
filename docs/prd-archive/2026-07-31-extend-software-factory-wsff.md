**Date**: 2026-07-31
**Status**: Draft
**Owner**: software-factory
**Task**: extend-software-factory-wsff
**Session**: `docs/knowledge/sessions/019fb4f8-7a69-7968-b884-f4902565e512/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019fb4f8-7a69-7968-b884-f4902565e512/decisions/01-three-phase-product-layer.md`

### Problem statement

The product/architecture layer currently has a single phase: grill → PRD → capture decisions. For Medium-to-Large tasks, this means structural decisions (system boundaries, data flow, module layout, type design) are left entirely to the implementation agent. The "Why Software Factories Fail" article presents strong evidence that models degrade codebase quality over time when given only functional requirements — they produce shotgun surgery, lazy type casts, and try-catch-wrapped-everything because there is no penalty for bad design in their training.

The factory needs to front-load structural alignment, catching bad decisions before they're expensive to fix, without adding rigid ceremony that would make the process burdensome.

### Solution overview

Extend the product/architecture layer with:

1. **Task categorisation** at pickup time — every task is classified as Trivial/Small/Medium/Large, which gates the analysis phases applied.
2. **Three-phase analysis model** — Product Design, System Architecture, and Program Design, applied sequentially based on task category.
3. **Single document accumulation** — all phases write into one plan document; no separate files per phase.
4. **Vertical Slicing as a guiding principle** — not a formal phase, but a preference communicated to the implementation agent.

### Architecture

**Data flow through the phases:**

```
Task picked up → Categorise (Trivial/Small/Medium/Large)
  │
  ├─ Trivial → oneshot implementation → capture decisions → done
  │
  ├─ Small → Product Design grill → plan document → implement
  │
  ├─ Medium → Product Design grill → Architecture grill → plan document → implement
  │
  └─ Large → Product Design grill → Architecture grill → Program Design grill → plan document → implement
```

**Key components:**

| Component | Role | Output |
|-----------|------|--------|
| Category gate | Determines which phases run | Category in task file |
| Product grill | Aligns on what and why | PRD sections (problem, solution, stories, decisions) |
| Architecture grill | Aligns on system structure | Architecture section (data flow, contracts, data model) |
| Program Design grill | Aligns on code shape | Program Design section (call stacks, file diffs, types) |
| Plan document | Single file accumulating all sections | `docs/prd-queue/<yyyy-mm-dd>-<slug>.md` |

**Changes to existing files:**

| File | Change |
|------|--------|
| `.agents/skills/product-layer/SKILL.md` | Added categorisation step, extended grill description, single-document accumulation |
| `docs/tasks/README.md` | Updated terminology, added Category field to template |
| `docs/tasks/<slug>.md` | Template now includes `**Category**:` field |

### User stories

1. As a person picking up a task, I can categorise it as Trivial/Small/Medium/Large so the right level of analysis is applied without over-engineering.
2. As a product-layer agent, I know which phases to run based on the task category and can follow the grill sequence without needing to decide what to do next.
3. As a reviewer, I can find architecture and program design decisions in the same document as the product requirements — one file, one place.
4. As an implementation agent, I receive a plan document that includes structural context (architecture, types, call stacks) where relevant, so I don't have to infer it.
5. As an implementation agent, I receive the Vertical Slicing principle as guidance but am free to apply it contextually per task.
6. As a future agent reading the knowledge base, I can trace the categorisation and phase model back to the decision that introduced it.

### Implementation decisions

- **Three phases, not four**: Vertical Slicing is a guiding principle, not a formal phase. The article's author says "I prefer to stay in the loop here" — rigidifying it would add ceremony without proven benefit. We'll iterate if real usage data suggests otherwise.
- **Single document per task**: All phases write into one file. The user explicitly rejected separate files as clutter.
- **No rigid templates for Architecture/Program Design sections**: The grill is the engine. The model drafts, the human argues, the notes become the sections. Structure emerges from the conversation, not from a template.
- **Category at pickup time**: Assigned once, based on explicit criteria (file count, module boundaries, new service/project). Recorded in the task file.
- **Existing state names preserved**: The lifecycle states `in-prd`, `prd-ready` etc. remain unchanged. They're just labels in a state machine.

### Testing decisions

This is a process change, not code. Testing is observational:
- The next Medium/Large task picked up after this change will be the first real test of the extended workflow.
- If the extended grill produces plan documents that feel too long or too shallow, we adjust the category criteria or the grill depth.
- If a task's category turns out to be wrong mid-session, the category can be upgraded (e.g., Small → Medium when new complexity is discovered).

### Out-of-scope items

- **Automating the categorisation**: Not yet. Category is assigned by the human/product-layer agent at pickup time. Could be automated later with learned heuristics.
- **Changing the directory layout**: `prd-queue/` and `prd-archive/` directory names stay as-is. The plan document still goes there.
- **Updating completed task files**: Existing task files that reference `PRD:` in their artifacts section are left as-is. New convention applies forward.
- **Adding templates for Architecture/Program Design sections**: Explicitly rejected. The grill produces the content.

### Further notes

- This model is deliberately lightweight. The article's core insight is that front-loading alignment saves review time, but the mechanism should be conversation, not paperwork.
- The Vertical Slicing principle should be added to the assembly line's shared context so implementation agents know the preference exists.
- The first Medium/Large task after this change will stress-test the categorisation criteria. Be prepared to adjust.