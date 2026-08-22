## Decision: Implementer container false-kill — tool-aware liveness + native session continuation

**Status**: accepted
**Date**: 2026-08-12 01:55
**Task**: [implementer-agent](../../../../tasks/implementer-agent.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: 1.

### Context

First live ("in the wild") run of the implementer harness on the real PRD
`extension-inline-agent` (feed_analyser → branch `public-release`) failed with
`DRIVER_EXIT=1` after exhausting all 3 respawns. The harness's safety rails
held (no push/PR leaked, task reverted to `prd-ready`, partial report archived)
but the run did not survive an ordinary container kill — the exact cattle
scenario brain/hands was designed to survive.

Evidence from the run dir
`~/.factory/runs/extension-inline-agent-20260812-010730`:
- The implementer was healthy and productive: **149 tool calls** across 3
  attempts, ~**333 lines** of real code written (manifest.json, sidepanel.html,
  sidepanel.js, plus untracked capture/agent-service/ and agent-client.js).
- It was killed mid-`node test/... | tail -40`. Piping to `tail` buffers all
  output until the pipe closes, so the container emitted **zero bytes** for
  several minutes while the test legitimately ran.
- The old commit-early contract produced **zero implementer commits**
  (`git log master..` empty) — all 333 lines were uncommitted working-tree state
  (though still durable on the host mount).
- Respawn tool-call counts were divergent (87 / 23 / 39) — a restart pattern,
  not a resume.

### Problem

Two coupled defects broke the resilience promise:

1. **Liveness watchdog false-positive.** The idle watchdog keys *only* on
   container stdout growth (`last_size` of the container log). A long-running
   tool that emits no bytes until completion (e.g. any `... | tail` buffered
   command, a heavy build, a slow test) is misclassified as "stuck" and killed.
2. **Continuity depended on the model committing.** The "commit-early" rule is
   soft — it only works if the model happens to commit, and commits don't even
   carry the model's working memory. A respawn started a cold `pi` with no
   memory of prior turns, so it re-explored from scratch.

### Alternatives

- **Raise `liveness_idle_sec`** (300 → 900+). Crude; a genuinely hung model
  would waste 15+ min per attempt, and it only narrows (not closes) the
  false-kill window.
- **Grep recent JSONL for empty `toolcall_delta`** to detect a "stalled stream"
  earlier. Fragile across pi versions and expensive to parse a big session log
  on every poll; also misdetects legitimate silent thinking.
- **Enforce commit-early mechanically** (fail/require ≥1 commit). Still can't
  recover in-flight memory at kill time, and pi's headless bash guard blocks
  literal `git commit`.
- **Host-side worktree snapshots** (considered, superseded). Mechanical, but the
  files are already durable on the host mount; the real gap is *model memory*,
  which a snapshot doesn't carry.
- **PROGRESS.md checkpoint file** (considered, rejected). Invented artifact
  papering over a gap that pi closes natively via session continuation.
- **Native pi session continuation** (chosen).

### Decision

1. **Make the liveness watchdog tool-execution-aware.** While a
   `tool_execution_start` has no matching `tool_execution_end`, skip the idle
   kill and let the hard overall `TIMEOUT_SEC` bound the run. Track the open-tool
   depth incrementally on the bytes appended each poll (count
   `"type":"tool_execution_start"` minus `"type":"tool_execution_end"`).
2. **Continuity via pi's native session (final choice).** The implementer never
   touches git; edits are durable on the host mount. The container runs pi with
   `--session-dir /sandbox/sessions --session-id $IMPL_UUID` (dropping
   `--no-session`), so the session persists on the host mount and a respawn
   reopens the same session-id and continues the existing conversation — full
   memory of prior turns and tools. A host-side worktree snapshot was considered
   but superseded: files are already durable on the mount, and session
   continuation provides model continuity for free.
3. **No PROGRESS.md.** An invented checkpoint is unnecessary; the driver's
   respawn passes a resume directive and reuses the same session identity.

### Rationale

This is the brain/hands philosophy applied honestly: durable state belongs on
the **host**, never in the disposable container and never contingent on a soft
model behavior (remembering to commit). Tool-aware liveness removes the
false-positive that turns an ordinary, survivable cattle death into a fatal,
whole-run failure. Native session continuation is preferred over an invented
PROGRESS.md because pi serializes the conversation itself and the driver just
reopens the same session-id on the host mount — no auxiliary artifact, no
model discipline required.

### Consequences

- Long silent verification `... | tail` commands will no longer be false-killed;
  a real model hang still gets bounded by the hard timeout and respawned.
- Respawned containers continue the SAME pi session (same `--session-id`), so
  the agent keeps its conversation/tool memory and resumes rather than
  restarting from scratch.
- The implementer never runs git; the host authors the single commit + push + PR
  at the end from the persistent worktree files.
- Large sessions need bounding/compaction for continuation to stay within model
  context; validate live.

### Revision triggers

- If pi's session continuation (`--session-id` reopen across a container respawn)
  proves lossy in practice (e.g. unflushed tail on kill) or too slow for very
  large sessions, revisit with host-side worktree snapshots or session
  compaction/truncation.
- If pi emits a reliable liveness heartbeat or precedable long-tool events, the
  tool-aware watchdog could be simplified.
