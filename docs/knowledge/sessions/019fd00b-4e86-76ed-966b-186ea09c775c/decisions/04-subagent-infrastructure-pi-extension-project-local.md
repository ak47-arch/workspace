## Decision: Subagent Infrastructure — Official Pi Extension, Project-Local, Read-Only Reviews

**Status**: accepted
**Date**: 2026-08-05 09:22
**Task**: extend-pm-assembly-line
**Project**: software-factory
**Session**: sessions/019fd00b-4e86-76ed-966b-186ea09c775c/session.jsonl

### Context

The PRD verification gate (decision `02-review-sub-agent-in-session-validation-gate`) is implemented as a read-only review sub-agent. The building block is pi's subagent infrastructure, which had to be installed. The factory workspace was not a monorepo; each sub-project is its own repo, and pi-related agents/extensions are managed per project.

During the install, discussion centred on which of the several opensource subagent extensions for pi to adopt, to keep to industry standards, and on where the agent definitions should live.

The full implementation of this task turned out to be completable in-session (infra installed + design decisions captured), so no separate PRD document was produced — the task was treated as complete directly.

### Problem

- Which pi subagent extension is the industry-standard choice, and whether pi officially endorses one.
- Where the review agent definitions should live (user-level vs project-local).
- Whether a formal PRD was needed given the implementation was already complete.

### Alternatives

- A third-party/community subagent extension. Rejected — pi has no marketplace of endorsed third-party subagent extensions, and a community fork is harder to keep aligned with upstream.
- User-level agents (`~/.pi/agent/agents/`). Rejected — the review gate is factory-specific and read-only; global availability across all sessions was undesired.
- **The subagent extension pi ships in its own repo + project-local agents (chosen).**

### Decision

- **Adopt the subagent extension pi ships in its own repository** (`packages/coding-agent/examples/extensions/subagent/`) as the industry-standard reference. Pi does not provide a native subagent tool in core nor endorse a third-party one; the shipped, in-tree-maintained example is the canonical choice. It is built on pi's native agent-definition format (markdown + YAML frontmatter with `name`, `description`, `tools`, `model`).
- **Project-local placement**: the subagent extension is symlinked into `.pi/extensions/subagent/` (consistent with the project's existing `.pi/extensions/` pattern), and the review agent definition lives at `.pi/agents/prd-reviewer.md`. Project-local agents are invoked with `agentScope: "project"` or `"both"` (a per-call param; no global config change).
- **Read-only by mechanism**: the `prd-reviewer` agent's `tools` list is `read, grep, find, ls, bash` — write tools (`edit`, `write`) are absent at the mechanism level, not just discouraged by prompt.
- **No separate PRD**: given the implementation was complete in-session, the task transitions to `complete` with the decisions as its durable record rather than producing a plan document.

### Rationale

- Keeps to industry standards: pi's own maintained extension + native agent format, not a community fork.
- Project-local keeps the factory's read-only review gate scoped to this repo and out of unrelated sessions.
- Enforcing read-only at the tool-list level (mechanism) is safer than relying on system-prompt instruction alone.
- Completing without a PRD avoided ceremony: the three design decisions (01, 02, 03) plus this one are the durable record of what was built and why.

### Consequences

- `.pi/extensions/subagent/` and `.pi/agents/prd-reviewer.md` committed to the factory workspace.
- The review sub-agent must be verified live (interactive pi session: `/reload`, then invoke with `prd-reviewer` + `agentScope: project`).
- pi-mono updated from upstream (434 commits) to provide the current subagent example and docs.
- Future stages (implementer agent) can define their own project-local agent profiles reusing the same extension.

### Revision triggers

- pi ships a native subagent feature or officially endorses a different extension, superseding the example.
- The project-local `agentScope` confirmation prompt proves disruptive, prompting reassessment of placement.
- A need emerges to run the review gate headlessly (no user session), requiring the mechanism-level read-only guarantee to be enforceable by the platform.
