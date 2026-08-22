## Decision: Evidence stream pathology — toolcall_delta replay is O(n²)

**Status**: accepted
**Date**: 2026-08-19 04:20
**Task**: [multi-repo-delivery-bookkeeping-prs](../../../../tasks/multi-repo-delivery-bookkeeping-prs.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Evidence stream pathology — toolcall_delta replay is O(n²)

### Context

Every factory run's `session.jsonl` and `container-*.log` balloon to hundreds of MB to multi-GB in minutes (this run: `container-1.log` 333MB + `session.jsonl` 334MB in 34 min; the remote run hit 2GB). A 60k-line session file held only 2 unique ids — the rest was replay.

### Problem

Why does the evidence grow so fast, and what should the durable artifact actually be?

### Decision (root cause + fix direction)

The growth is **stream-replay pathology**: the raw pi event stream emits a `message_update → toolcall_delta` for **every keystroke** of the agent composing a tool call, and each delta event re-emits the **entire accumulated partial arguments** object — twice per event (`assistantMessageEvent.partial` *and* `message`). So typing one bash command is O(n²) bytes. The durable evidence should therefore be:
- **message-level events only** (drop the per-delta `toolcall_delta` replay), and
- sanitized + compressed (the existing `bin/sanitize-session.sh` + "compress all session files" backlog already point this way).

**Evidence stripping at delivery works**: the implementer run dir went from 1.1GB of raw logs to 4.9MB after delivery stripped the heavy logs.

### Rationale

The run's real value is the message-level trace (tool calls, results, reports, verdicts), not the token-by-token reconstruction of argument typing. Dropping deltas from the durable log preserves the narrative while cutting storage by orders of magnitude.

### Consequences

- Local runs are unaffected functionally, but rapidly consume disk (multi-GB per Large task).
- Remote runs previously failed GitHub's 100MB evidence-push cap for the same reason — this is the single root cause behind the remote evidence failures.

### Revision triggers

- A streaming/logging layer (pi or herdr) that de-duplicates or omits per-delta replay natively.
