## Decision: Implementer container false-kill — tool-aware liveness + host-owned durable snapshots

**Status**: accepted
**Date**: 2026-08-12 01:55
**Task**: implementer-agent
**Project**: software-factory
**Session**: sessions/019fecde-70b4-78e7-ab7d-e91886af42a7/session.jsonl

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
- Worktree clone showed **zero implementer commits** (`git log master..` empty)
  — all 333 lines were uncommitted working-tree state.
- Respawn tool-call counts were divergent (87 / 23 / 39) — a restart pattern,
  not a resume-from-commit pattern.

### Problem

Two coupled defects broke the resilience promise:

1. **Liveness watchdog false-positive.** The idle watchdog keys *only* on
   container stdout growth (`last_size` of the container log). A long-running
   tool that emits no bytes until completion (e.g. any `... | tail` buffered
   command, a heavy build, a slow test) is misclassified as "stuck" and killed.
2. **Durable memory depended on the model committing.** The "commit-early for
   respawn recovery" rule is soft — it only works if the model happens to
   commit. In the wild it didn't (0 commits), so a killed container lost ~all
   progress and respawns restarted from scratch, exhausting the cap and failing
   the task.

### Alternatives

- **Raise `liveness_idle_sec`** (300 → 900+). Crude; a genuinely hung model
  would then waste 15+ min per attempt, and it only narrows (not closes) the
  false-kill window.
- **Grep recent JSONL for empty `toolcall_delta`** to detect a "stalled stream"
  earlier. Fragile across pi versions and expensive to parse a 100 MB session
  log on every poll; also misdetects legitimate silent thinking.
- **Enforce commit-early mechanically** (fail/require ≥1 commit before a long
  verification). Still can't recover the uncommitted work already in flight at
  kill time, and pi's headless bash guard blocks literal `git commit`.
- **Host-owned periodic snapshots** (chosen). The driver snapshots the worktree
  (committed + uncommitted + untracked) into the run dir and restores it on
  respawn, so cattle death is survivable regardless of whether the model ever
  commits.

### Decision

1. **Make the liveness watchdog tool-execution-aware.** While a
   `tool_execution_start` has no matching `tool_execution_end`, skip the idle
   kill and let the hard overall `TIMEOUT_SEC` bound the run. Track the open-tool
   depth incrementally on the bytes appended each poll (count
   `"type":"tool_execution_start"` minus `"type":"tool_execution_end"`).
2. **Add host-owned durable snapshots.** The driver periodically snapshots the
   worktree into the run dir and restores it before each respawn, so the brain
   holds durable state and the container is genuinely disposable cattle.

### Rationale

This is the brain/hands philosophy applied honestly: durable state belongs on
the **host**, never in the disposable container and never contingent on a soft
model behavior (remembering to commit). A snapshot is mechanical and verifiable;
commit-early is advisory. Tool-aware liveness removes the false-positive that
turns an ordinary, survivable cattle death into a fatal, whole-run failure.

### Consequences

- Long silent verification `... | tail` commands will no longer be false-killed;
  a real model hang still gets bounded by the hard timeout and respawned.
- Respawned containers resume from a host snapshot instead of restarting from
  scratch, so partial progress (uncommitted work at kill time) is preserved.
- Commit-early remains valuable for durable git history and story-level review,
  but is no longer load-bearing for crash recovery.
- Adds snapshot/restore cost and complexity to the driver; restore must be
  careful with untracked files and a running container's in-flight writes.

### Revision triggers

- If a more reliable liveness signal emerges (e.g. pi emitting a heartbeat or
  precedable long-tool events that pi itself will not produce).
- If commit-early becomes *mechanically* enforced by the driver (e.g. requiring
  ≥1 commit before the respawn cap advances), making host snapshots redundant.
- If pi's headless bash guard is relaxed to permit plain `git commit` (reducing
  the implementer's friction to committing early).
