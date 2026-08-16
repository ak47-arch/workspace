## Decision: Capture extension agent — follow-up turns, persistence, and reconnect UX fixes

**Status**: accepted
**Date**: 2026-08-15 22:40
**Task**: x-capture-instrument
**Project**: feed-analyser
**Session**: sessions/01a00610-13dd-72ee-a5d4-2f3765c07cb3/session.jsonl

### Context

The Capture extension's inline agent (pi SDK in a local Node service, `capture/agent-service`, one tool `fetch_url`) showed a broken multi-turn UX: the first answer rendered, but every follow-up produced an empty bubble with a `$0.00000` "model …" footer and no reply. The panel also failed to render reasoning, markdown, or error state, and died permanently after service restarts.

### Problem

Four distinct defects stacked up:

1. **Follow-ups never ran.** `agent.js` called `AgentSession.followUp()`. In the pi SDK, `followUp()` only *enqueues* a message that the native agent loop drains while a run is active (`agent-loop.js`: "Check for follow-up messages … if present, continue the outer loop"). After `agent_end` the run has returned and the agent is idle — nothing starts a new run, so the queued message sits forever. The correct "start the next turn in the same conversation" primitive is `session.prompt()`. Empirically reproduced server-side: `ask → settled → follow_up` produced zero events for 90s; switching to `prompt()` produced a second `settled`.

2. **Persistence overwrote turns.** `onSettled(event.messages)` receives only the *current* turn's messages (pi hands back per-run messages on `agent_end`). Each settlement rewrote `session.jsonl` from scratch, so a follow-up replaced turn 1 instead of appending — the persisted evidence silently lost conversation history.

3. **Panel WS client gave up permanently.** `agent-client.js` stopped reconnecting after 8 failed attempts (~2 min backoff), stranding the panel in "Agent unavailable" forever after any transient service restart.

4. **No recovery after service restarts.** Restarting the service drops its in-memory `captureId → handle` map; a follow-up then errored "No active conversation" with no recovery path in the UI.

### Alternatives

- **Keep `followUp()` and rely on SDK queue draining** — Rejected. The queue is only drained inside a live run; there is no always-on message pump in the SDK. The host runtime (pi CLI/RPC mode) is responsible for calling `prompt()` per user message, so the capture agent service must act as its own mini-runtime and do the same.
- **Persist only on final save (post-Save)** — Rejected. Evidence should be durable as the conversation happens; losing turns before Save made timed-out conversations unreviewable.
- **Panel-side reconnect with a large-but-finite attempt cap** — Rejected. Any finite cap re-creates the dead-until-reload state; infinite retry with capped backoff (30s max) is the correct resilience level for a local service that restarts frequently during development.
- **Recreate the server handle on every WS connection for known captureIds** — Deferred. Simpler and more robust to re-deliver as a fresh `ask` carrying the prior transcript (panel `resendAsAsk()`) than to try to resurrect in-memory session state.

### Decision

- `agent.js`: follow-ups use `session.prompt()` (not `session.followUp()`), against the same in-memory session so context is retained.
- `server.js`: `onSettled` accumulates `handle.allMessages` across turns and persists the combined conversation; every event is logged to stdout (`[ws]`, `[ask]`, `[follow_up]`, `[event]`) for diagnosis.
- `extension/agent-client.js`: reconnect forever with capped exponential backoff (max 30s) — no permanent give-up.
- `extension/sidepanel.js`: `onError` with "No active conversation" triggers `resendAsAsk()` (re-deliver the pending prompt as an `ask` with the prior transcript); empty settlements render an explicit "⚠ No reply" bubble; `onThinking` streams `thinking_delta` into a collapsible Reasoning block; assistant replies render markdown (hand-rolled, HTML-escaped).
- Provider request timeout set (`retry.provider.timeoutMs: 60s`, 2 retries) so hangs fail fast instead of the SDK's long default.

### Rationale

pi's loop is native and turn-scoped: one run per `prompt()` call, with `steer()`/`followUp()` as *in-loop* concurrent queues. The capture service is the host runtime, so it must own the "deliver each user message via prompt()" responsibility — the original code assumed `followUp()` was that delivery mechanism. Accumulated persistence matches the session-evidence model (one artefact = full conversation). Infinite reconnect + transcript re-delivery gives a normal chat UX across the frequent service restarts that local development entails.

### Consequences

- Multi-turn conversations now work end-to-end and persist as one cumulative `session.jsonl`.
- The service acts as an explicit mini-runtime for pi (ask/follow-up → `prompt()`), which is the seam where future tools/skills plug in.
- Every settlement rewrites the full session file (grows linearly with turns); compaction is currently disabled in `agent.js`, so long conversations resend the whole thread to the model.
- Extensions must be reloaded after panel changes (standard unpacked-extension behaviour).

### Revision triggers

- A pi SDK release changes `AgentSession.followUp()` semantics to start turns from idle — the `prompt()` workaround could revert to the native API.
- Long conversations exceed practical context/cost with compaction disabled — revisit enabling pi compaction or trimming the transcript sent to the model.
- The reconnect/re-delivery flow causes duplicate messages or lost turns after service restarts in real browser use.
- Adding more tools (read/bash/etc.) changes the loop/streaming shape enough to warrant a shared message-pump helper.
