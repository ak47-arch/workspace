## Decision: Single Factory Context Document for Token-Efficient Context

**Status**: accepted
**Date**: 2026-08-01
**Task**: combine-factory-context-factory-txt
**Project**: software-factory
**Session**: sessions/019fbd12-7ea3-7152-9eec-f865cf69d6f7/session.jsonl

### Context

The workspace had two separate files at the top of the progressive disclosure chain: `docs/factory.txt` (factory model definition) and `docs/factory-context.md` (project inventory, vision docs, pointer index). Both were referenced from AGENTS.md as entry points. The factory.txt had become stale — it was written before significant work on the three-phase product model, task lifecycle management, knowledge base infrastructure, and vision doc convention.

### Problem

Maintaining two files with overlapping concerns created unnecessary maintenance surface and forced agents to read two files to orient themselves. The factory.txt contained a long "Knowledge Base — Deep Dive" section with narrative prose, counts that go stale (e.g., "2/4 core projects have vision docs", "only one knowledge base entry"), and a "What Still Needs Work" section that duplicated information tracked in tasks.txt and KNOWN_ISSUES.md. The context was not optimized for fast agentic search — agents had to parse verbose narrative to find current state.

### Alternatives

- **Patch factory.txt only** — update the narrative to reflect current state. Rejected because it leaves two files for agents to navigate, and the prose would go stale again.
- **Keep both files, improve cross-referencing** — rejected because it adds another layer of indirection rather than reducing it.
- **Merge into a new file** — rejected because it would break the existing AGENTS.md pointer string and require updating more references.

### Decision

Merge factory.txt into factory-context.md, producing a single `docs/factory-context.md` that contains:
1. Factory model (4 components, one rule)
2. Progressive disclosure chain (diagram + brief description)
3. Project inventory (table)
4. Vision/Design Intent (table)
5. Pointers (links to tasks, known issues, knowledge base, etc.)

The merged document uses:
- **No stale counts** — no "X of Y projects have vision docs", no "N+ decisions". The tables show what exists, and the status column handles the rest.
- **No narrative deep-dive** — the knowledge base is described in 4 sentences + a diagram, not a page of prose. The mechanism is described, not the inventory.
- **One artifact per component** — product/architecture produces one artifact (the plan document). Design decisions are a byproduct into the knowledge base, not a separate output.
- **Tight scannable structure** — the agent reads the factory model, sees the disclosure chain, checks the project table, and follows pointers. All in one file.

### Rationale

- Single file means single maintenance surface — when the factory model changes or a project status updates, one file is touched.
- Token-efficient — the merged doc is ~2.5KB, still under the ~3KB threshold. The agent gets oriented in one read.
- No stale counts — the file never needs updating just because a session added a new decision or a vision doc was written. The tables and mechanism are invariant.
- The disclosure chain is simple and clear: AGENTS.md → factory-context.md → discovery layer → knowledge base (last resort).

### Consequences

- Easier: maintaining the context layer means editing one file instead of two.
- Easier: agents orient themselves in one read instead of two.
- Changed: `docs/factory.txt` deleted from the workspace.
- Changed: AGENTS.md, CLAUDE.md, and product-layer SKILL.md updated to point to `docs/factory-context.md` instead of `docs/factory.txt`.
- Added: remaining gaps from "What Still Needs Work" moved to KNOWN_ISSUES.md (Issues 5-7).
- Deprecated: the "What Still Needs Work" section pattern — all gaps now live in KNOWN_ISSUES.md or tasks.txt.

### Revision triggers

- If the factory model is restructured (add/remove/rename components) — the file needs updating.
- If the merged document grows beyond ~4KB and becomes unwieldy — consider splitting back into model + inventory.
- If the knowledge base becomes a primary discovery layer rather than a last resort — the disclosure chain description needs updating.