## Decision: Large documents are written incrementally, never in one tool call

**Status**: accepted
**Date**: 2026-08-09 21:18
**Task**: [extension-inline-agent](../../../../tasks/extension-inline-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Write large documents incrementally

### Context

Writing the extension-inline-agent PRD (Large: Product Design + System
Architecture + Program Design, ~200 lines) failed repeatedly over nearly an
hour. Every attempt produced `terminated` / `Retry failed after 3 attempts:
terminated` and never a file on disk. The failure looked like an environment
or harness problem.

### Problem

Why did a single `write` of the whole PRD keep dying, and how should large
documents be written reliably in this workspace?

### Root cause

The entire file content was being emitted inside one `write` tool call. The
model's response hit its max-output-token limit mid-generation — truncated
inside the file-content JSON string — yielding a broken tool call
(`stopReason: "terminated"`), which the retry logic retried identically
three times, failing each time. Nothing was ever written because the call
never completed. It is a self-inflicted payload-size problem, not a repo or
harness fault. (Same class of failure later killed subagent runs rendering
very large tool results.)

### Alternatives

- Keep trying single-shot writes: rejected — provably unworkable for >~150
  line documents on this model.
- Have a subagent write the PRD: not needed — chunking solves it in the main
  session and keeps the transcript in the session file.

### Decision

Write large documents **incrementally**:

1. `write` the skeleton + first section (header + Product Design) — small
   enough to complete in one call.
2. Append remaining sections (System Architecture, then Program Design) with
   `edit` calls anchored on the file's last line.
3. Verify after each step (`wc -l`, `grep "^## "`) before proceeding.

Each chunk must stay well under the model's output limit; when in doubt,
chunk again. If a tool call truncates mid-argument, retrying the same giant
payload is futile by construction.

### Rationale

Small calls complete reliably; appends are idempotent and verifiable; the
cost is a few extra tool calls. The failure mode is fully mechanical and
deterministic, so the mitigation is fully deterministic too.

### Consequences

- The extension PRD (329 lines, 9 sections) was completed in three chunks
  after the single-shot attempts had failed ~an hour.
- Future PRD authors should chunk from the start — a Large PRD is ~300+ lines
  and cannot fit one call on the default model.

### Revision triggers

- If the model's output limit increases past single-call PRD sizes, chunking
  becomes unnecessary ceremony and can be dropped.
- If pi supports incremental streaming into files, this pattern can be
  replaced.
