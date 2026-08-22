## Decision: Mission Control Deprecation

**Status**: accepted
**Date**: 2026-07-30 21:31
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Remove mission-control from the workspace entirely: - Delete the mission-control/ directory - Archive the remote GitHub repo (ak47-arch/mission-control) - Remove all refe

### Context

Mission Control was a Rust-based session monitor (Phase 3 complete) that collected pane state from herdr and Pi signals, providing a TUI and web dashboard for monitoring coding-agent sessions. It was built as a read-only birds-eye view over running agent panes, with a detailed PRD and DESIGN document.

### Problem

The project was fully implemented and working, but there was no active use or ongoing maintenance need. The functionality overlapped with other observability directions (software factory monitoring automation, Langfuse integration) and maintaining a Rust workspace with multiple crates (mc-schema, mc-core, mc-binary) for an unused tool was not worth the upkeep cost.

### Alternatives

- **Keep as-is**: Leave the code in place, mark as deprecated in docs. Would still accumulate bitrot and confuse new agents reading the workspace.
- **Soft deprecation**: Mark as deprecated in docs, stop active development, but leave code locally. The code would still need to be carried in the workspace.
- **Full removal**: Delete the directory, archive the remote repo, clean up all references from workspace docs. This is what was chosen.

### Decision

Remove mission-control from the workspace entirely:
- Delete the `mission-control/` directory
- Archive the remote GitHub repo (`ak47-arch/mission-control`)
- Remove all references from workspace documentation (factory-context, projects inventory, openwiki pages, quickstart, architecture overview)
- Mark the task as complete in `tasks.txt`

### Rationale

- No active users or downstream consumers of the tool
- Maintaining a complex Rust workspace for an unused tool imposes cognitive load on agents reading the workspace
- The goals of automated monitoring and observability are better served by the Langfuse integration and software factory monitoring tasks already in the pipeline
- Full removal is cleaner than partial deprecation — no stale links, no dead code to navigate around
- The knowledge base session files remain as historical records of the design decisions made during mission-control's development

### Consequences

- The workspace is simpler — one fewer project to track, document, and maintain
- Future agents won't be confused by a dead project when scanning the workspace
- The herdr entry in the open-source projects table was updated to reflect no active consumer
- The architecture overview diagram is cleaner without the mission-control box
- All design decisions, PRD, and implementation details from mission-control's development remain in the knowledge base session files for reference

### Revision triggers

- If someone decides they want a pane-session monitoring dashboard, the mission-control PRD and DESIGN docs in the knowledge base provide a solid starting point for rebuilding
- If the software factory monitoring automation task is picked up and finds need for the ideas in mission-control
