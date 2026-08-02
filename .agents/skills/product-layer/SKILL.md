---
name: product-layer
description: "Start a product/architecture session. Produces one artifact per task: the plan document."
disable-model-invocation: true
---

# Product Layer — Software Factory

> Reference base: /home/anupam/Desktop/workspace (workspace root) — all relative paths in this skill resolve from there, not from the skill directory.

You are now operating the **product/architecture layer** of the software factory. This is the UX layer — the only interface the user interacts with directly. Your job is to understand what the user wants to build, sharpen it into a concrete plan, and produce one artifact: the **plan document** — a forward-looking spec saved to `docs/prd-queue/` (moved to `docs/prd-archive/` when the task is complete). For Medium/Large tasks, this single document accumulates sections from three phases: Product Design, System Architecture, and Program Design.

Design decisions are captured into the knowledge base as a byproduct of the process. The task file (`docs/tasks/<slug>.md`) is created for lifecycle tracking.

**For Trivial tasks** — single file, no new logic — skip the plan document, complete the task directly in the session. Design decisions are captured as they emerge.

## Before you begin

### 0. Sync the workspace

Run `git pull` to bring the workspace up to date with the remote. The task dashboard may have modified `docs/tasks.txt` from another device, so this ensures the file is current before any work begins.

```bash
cd /home/anupam/Desktop/workspace && git pull --rebase
```

If there are merge conflicts, resolve them manually before proceeding.

### 1. Read the model

Read `docs/factory-context.md` to understand the software factory model and how this layer fits.

Then read `docs/tasks.txt` and prompt the user to pick a task to work on. The session centres around that task — everything from grilling to the PRD is scoped to it.

**When a task is picked up**, derive a slug from its title (e.g. `github-browser-auth-flow` from "implement github browser authentication flow for project restore"), then:

1. **Categorise the task** — assign one of:
   - **Trivial**: single file, no new logic (oneshot directly)
   - **Small**: 1–3 files, existing seam (Product Design only)
   - **Medium**: crosses modules, 3+ files (Product Design + System Architecture)
   - **Large**: new service/project, major refactor (all three phases)

2. **Annotate `docs/tasks.txt`** — append `[<slug>]` to the end of that task's line so the mapping is explicit and deterministic. This is a one-time edit — the slug never changes after assignment.

3. **Create the task file** at `docs/tasks/<slug>.md` with status `in-prd` and the category recorded. The task file is the reference hub that will accumulate links to the plan document, sessions, and decisions as work progresses.

Task file template:
```markdown
# Task: <slug>

**Status**: in-prd
**Category**: Trivial | Small | Medium | Large
**Project**: <project>
**Created**: <yyyy-mm-dd HH:MM>
**Source**: docs/tasks.txt — `<exact text from the tasks.txt line>`

## Artifacts

- Plan: _(will be created)_

## Sessions

- _(this session)_

## Decisions

- _(will be captured inline)_
```

## Workflow

### 1. Read the technique guides

These describe the process you'll follow. Read their content into this session:

- `opensource/skills/docs/engineering/grill-with-docs.md` — the grilling process: one question at a time, resolve vocabulary, capture decisions
- `opensource/skills/docs/engineering/to-spec.md` — synthesising a spec from aligned understanding
- `opensource/skills/docs/engineering/wayfinder.md` — for large, foggy efforts (skip if scope is small)
- `opensource/skills/docs/productivity/grill-me.md` — stateless grilling alternative

### 2. Grill

Follow the grilling process: one question at a time, resolve dependencies between decisions before moving on. Offer your own recommended answer for every question. Answer questions from the codebase where possible instead of asking the user.

**For Medium tasks**, after aligning on product scope, continue grilling on system architecture — data flow, endpoint contracts, data model changes. **For Large tasks**, also grill on program design — call-stack trees, file-tree diffs, key types and signatures.

The grill is the engine: the plan document's sections are the notes that emerge from each grill. No rigid templates — the model drafts, the human argues, the understanding is captured.

**As you resolve decisions, capture them.** Every hard-to-reverse decision gets recorded as a structured knowledge entry on the spot — not batched at the end. Use the design decision format below.

### 3. Synthesise the plan document or complete the task

**Trivial task?** Skip the plan document — implement the task directly in the session. Capture any design decisions that emerge. Then go to step 4.

Otherwise, once alignment is reached across all phases relevant to the task's category, synthesise a single plan document that accumulates sections from each grill. The document is saved to `docs/prd-queue/` as `<yyyy-mm-dd>-<slug>.md`

Every PRD starts with a header block that ties it to its session and decisions:

```
**Date**: <yyyy-mm-dd HH:MM>
**Status**: Draft | Review | Final
**Owner**: <team or initiative>
**Task**: <slug>
**Session**: `docs/knowledge/sessions/<session-uuid>/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/<session-uuid>/decisions/<sequence>-<slug>.md`
  - ... (list each decision file)
```

The Decisions field lists the individual decision files so downstream processes can trace each settled choice back to its full record.

Body sections (base template — additional sections accumulate from extended grills for Medium/Large tasks):

- **Problem statement** — what is broken or missing, and why it's worth solving
- **Solution overview** — the shape of the fix at a high level
- **User stories** — numbered, independently checkable behaviours
- **Implementation decisions** — choices already settled during the conversation
- **Testing decisions** — the seams the feature will be tested at
- **Out-of-scope items** — what this deliberately does not cover
- **Further notes** — anything else worth carrying forward

**For Medium tasks**, an `## Architecture` section is added after the extended grill (data flow, endpoint contracts, data model changes). **For Large tasks**, a `## Program Design` section is also added (call-stack trees, file-tree diffs, key types and signatures). All sections live in the same document — no separate files.

Save to: `docs/prd-queue/<yyyy-mm-dd>-<slug>.md`

### 4. Finalise

Call `bin/transition-task.sh` to bookkeep the lifecycle transition. The tool handles everything:

```bash
# After a PRD session (plan is done, task is ready for implementation):
bin/transition-task.sh <slug> --to prd-ready --session <session-uuid>:planning --decisions <decision-files...>

# After implementing a Trivial task directly in session:
bin/transition-task.sh <slug> --to complete --session <session-uuid>:planning --decisions <decision-files...>

# After completing a task that had a PRD (archives PRD automatically):
bin/transition-task.sh <slug> --to complete --session <session-uuid>:implementation --decisions <decision-files...>
```

This will:
- Update the task file status, sessions, and decisions
- Move the task line in `docs/tasks.txt` to the correct status section
- Archive the PRD (if transitioning to `complete`)
- Commit the changes

**Do not manually edit** `docs/tasks.txt` or the task file for lifecycle transitions — always use the script.

---

## Design decision capture format

Every decision entry uses this structure:

```
## Decision: <title>

**Status**: proposed | accepted | deprecated | superseded
**Date**: <yyyy-mm-dd HH:MM>
**Task**: <slug>
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