---
name: product-layer
description: Start a product/architecture session. Produces PRDs and structured design decisions.
disable-model-invocation: true
---

# Product Layer — Software Factory

> Reference base: /home/anupam/Desktop/workspace (workspace root) — all relative paths in this skill resolve from there, not from the skill directory.

You are now operating the **product/architecture layer** of the software factory. This is the UX layer — the only interface the user interacts with directly. Your job is to understand what the user wants to build, sharpen it into a concrete plan, and produce two durable artifacts:

1. **PRD** — forward-looking spec, saved to `docs/prd-queue/`
2. **Design decisions** — backward-looking record, captured in `docs/knowledge/`

**For trivial tasks** — if the scope is small enough that a PRD would be more ceremony than value — skip the PRD, complete the task directly in the session, and save only the design decisions.

## Before you begin

Read `docs/factory.txt` to understand the software factory model and how this layer fits.

Then read `docs/tasks.txt` and prompt the user to pick a task to work on. The session centres around that task — everything from grilling to the PRD is scoped to it.

## Workflow

### 1. Read the technique guides

These describe the process you'll follow. Read their content into this session:

- `opensource/skills/docs/engineering/grill-with-docs.md` — the grilling process: one question at a time, resolve vocabulary, capture decisions
- `opensource/skills/docs/engineering/to-spec.md` — synthesising a spec from aligned understanding
- `opensource/skills/docs/engineering/wayfinder.md` — for large, foggy efforts (skip if scope is small)
- `opensource/skills/docs/productivity/grill-me.md` — stateless grilling alternative

### 2. Grill

Follow the grilling process: one question at a time, resolve dependencies between decisions before moving on. Offer your own recommended answer for every question. Answer questions from the codebase where possible instead of asking the user.

**As you resolve decisions, capture them.** Every hard-to-reverse decision gets recorded as a structured knowledge entry on the spot — not batched at the end. Use the design decision format below.

### 3. Synthesise the PRD or complete the task

**Trivial task?** Skip the PRD — implement the task directly in the session. Capture any design decisions that emerge. Then go to step 4.

Otherwise, once alignment is reached, write the PRD. Follow the spec structure from to-spec.

Every PRD starts with a header block that ties it to its session and decisions:

```
**Date**: <yyyy-mm-dd>
**Status**: Draft | Review | Final
**Owner**: <team or initiative>
**Session**: `docs/knowledge/sessions/<session-uuid>/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/<session-uuid>/decisions/<sequence>-<slug>.md`
  - ... (list each decision file)
```

The Decisions field lists the individual decision files so downstream processes can trace each settled choice back to its full record.

Body sections:

- **Problem statement** — what is broken or missing, and why it's worth solving
- **Solution overview** — the shape of the fix at a high level
- **User stories** — numbered, independently checkable behaviours
- **Implementation decisions** — choices already settled during the conversation
- **Testing decisions** — the seams the feature will be tested at
- **Out-of-scope items** — what this deliberately does not cover
- **Further notes** — anything else worth carrying forward

Save to: `docs/prd-queue/<yyyy-mm-dd>-<slug>.md`

### 4. Finalise

The session is complete. The PRD sits in the queue; the decision records sit in the knowledge base. Both will be picked up asynchronously by downstream layers.

---

## Design decision capture format

Every decision entry uses this structure:

```
## Decision: <title>

**Status**: proposed | accepted | deprecated | superseded
**Date**: <yyyy-mm-dd>
**Session**: <path to session.jsonl>

### Context

What was happening in the workspace that framed this decision.

### Problem

The specific tension or requirement being addressed.

### Alternatives

What else was considered and why each was rejected or deferred.

### Decision

What was chosen.

### Rationale

Why this path, acknowledging trade-offs.

### Consequences

What changes — things that become easier, harder, or deprecated.

### Revision triggers

Conditions that would make this decision worth re-examining.
```

### Where to save

Each decision goes in the session's decision directory:
```
docs/knowledge/sessions/<session-uuid>/decisions/<sequence>-<slug>.md
```

Use the `save-knowledge` skill to handle path creation, sequence numbering, session file copying, and index updates automatically.

---

## Glossary

If a shared vocabulary emerges during grilling, write resolved terms into `CONTEXT.md` at the workspace root. The glossary stays a glossary: pure vocabulary, no implementation details, no spec.