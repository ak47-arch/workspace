## Decision: Browser control by the agent deferred to a follow-on phase

**Status**: accepted
**Date**: 2026-08-08 21:43
**Task**: [extension-inline-agent](../../../../tasks/extension-inline-agent.md)
**Project**: feed_analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Defer browser control to a follow-on phase on the same architecture.

### Context

The user asked whether the pi agent could control the browser window via the
extension (scroll, click, expand threads on the live x.com page). It is
feasible: the bridge already links pi to the extension; browser tools would
proxy `execute()` through the bridge → extension → content script → live DOM
and return results as tool results.

### Problem

Is browser control in scope for this task, and how should it be bounded?

### Alternatives

- **Include browser-control tools now** — rejected by the user ("leave
  browser control for now"). Adds a second capability surface and risks
  scope creep on an already-large task.
- **Never** — rejected: it layers cleanly onto the same bridge later.

### Decision

Defer browser control to a follow-on phase on the same architecture. When it
is built it must be bounded to read/scroll/expand actions (reversible, no
posting/engagement); the long-lived WebSocket must hang off the **content
script** (not the MV3 service worker, which is killed after ~30s idle), and
navigation that would destroy the content script needs special handling.

### Rationale

The core value (agent reasoning → artefact → searchable KB + session evidence)
does not depend on browser control; deferring keeps this task bounded while
preserving the architectural seam (bridge + extension) for a later phase.

### Consequences

- No browser tools in v1; the agent reaches content only via the capture tree
  and `fetch_url`.
- Recorded design constraints (socket on content script, read-only actions)
  so the future phase starts from settled boundaries.

### Revision triggers

- When the user wants the agent to explore the live page (expand threads, read
  more comments) or gather context beyond the curated tree.
