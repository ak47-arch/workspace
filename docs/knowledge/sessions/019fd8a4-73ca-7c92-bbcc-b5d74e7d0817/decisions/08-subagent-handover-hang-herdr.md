## Decision: Subagent runs hang at handover — herdr heartbeat root cause + persist-step mitigation

**Status**: accepted
**Date**: 2026-08-09 21:18
**Task**: extension-inline-agent
**Project**: software-factory
**Session**: sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/session.jsonl

### Context

Every subagent invocation (prd-reviewer runs of the extension PRD) exhibited
the same failure: the child completed its task — the full report was produced
and, in round 2, written to disk — then the tool call never handed back to
the parent; the user had to press Esc, which produced `Subagent was aborted`
with an empty `details` object and no persisted transcript. We assumed the
built-in subagent implementation was at fault and searched pi's compiled
output in vain.

### Problem

Why does a subagent that has finished its work stay "stuck" permanently, and
why is its context not saved anywhere?

### Root cause (reproduced and bisected)

1. **What the subagent tool does**: it spawns a separate
   `pi --mode json -p --no-session` child and waits for its `close` event.
   `--no-session` means the child never persists a transcript (ephemeral) —
   all context lives only in the parent's memory.
2. **Reproduction**: the exact child command completed the run
   (`message_end` with `stopReason:"stop"`, then `agent_settled`) and then
   never exited (killed by a 90 s `timeout`).
3. **Bisection**: from `/tmp` (no project extensions) the identical command
   exits in ~5 s. Loading each `.pi/extensions/*.ts` via `pi -e` one at a
   time pinned the hang to **`herdr-agent-state.ts`** (herdr's pi
   integration, v6): a heartbeat `setInterval(..., 10_000)` at line ~354 with
   **no `.unref()` and no `clearInterval`** anywhere — every other timer in
   the file is unref'd. The interval keeps the child's event loop alive
   forever after `agent_settled`, so `process exit` never happens, the
   parent's `close` handler never fires, and the tool call pends forever.
4. **Abort path is lossy**: on Esc the parent throws
   `"Subagent was aborted"` before constructing the result, so `details`
   comes back `{}` — the in-memory transcript is discarded. Only this error
   string is recorded in the parent's session JSONL.

### Alternatives

- Fix nothing, keep Esc-ing: rejected — every subagent use hangs.
- Move subagent runs outside the workspace's `.pi/extensions` (run from
  `/tmp`): works, but removes project context the agent needs (factory docs,
  PRD, code), so it's only a diagnostic trick, not a fix.
- Rely on pi's normal completion path: rejected as the only mitigation —
  normal completion does hand back correct output, but the herdr hang must be
  fixed regardless.

### Decision

- **Fix the root cause** (pending): patch `herdr-agent-state.ts` — `.unref()`
  the heartbeat interval and `clearInterval` it in `session_shutdown`
  (mirroring the other timers). The file header warns it is managed by herdr
  and overwritten on reinstall, so the patch must be re-appliable and/or
  reported upstream (herdr can fix it in the integration itself).
- **Persist-step pattern (adopted)**: any subagent whose output must survive
  (reviews, reports) must write its deliverable **to a file inside the task**
  (e.g. `docs/reviews/<date>-<slug>[-v2].md`) using the `write` tool rather
  than relying on the returned tool result. The file lands mid-run, so even
  an abort preserves the work — this is why round-2 review survived.
- Treat `Subagent was aborted` as **"rerun, don't despair"** — reviewers are
  read-only and deterministic on the same inputs, so a rerun is cheap once
  the persist-step is in place.

### Rationale

The hang is a process-lifecycle bug in the herdr integration, not in the
agent logic; the empirical bisection (clean exit without extensions / clean
exit with every extension except herdr) made the culprit unambiguous. The
persist-step decouples deliverable durability from the flaky handover path —
defence in depth rather than waiting for the fix. It also matches the
factory's evidence philosophy: the report file is the artefact, the tool
result is just the handover.

### Consequences

- Subagent runs remain unreliable until the patch lands; any new subagent
  task in the factory should include a persist-step by default.
- `docs/reviews/` now holds round-1 and round-2 PRD review reports as
  artefacts (the extension-inline-agent PRD gate evidence).
- The gdrive PRD/review flows and any future prd-reviewer invocation should
  reuse the same pattern.

### Revision triggers

- When herdr updates `herdr-agent-state.ts` (reinstall overwrites the patch),
  re-apply the `.unref()` / `clearInterval` fix or confirm herdr shipped it
  upstream.
- If pi fixes json-mode exit or the abort path (returning accumulated
  `messages`/`details` on abort), the persist-step pattern can be relaxed —
  but keeping it costs little.