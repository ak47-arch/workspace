## Decision: Agent runs on pi SDK in a local Node service; extension is the UI

**Status**: accepted
**Date**: 2026-08-08 21:43
**Task**: extension-inline-agent
**Project**: feed_analyser
**Session**: sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/session.jsonl

### Context

The capture instrument (MV3 extension + dumb FastAPI server) currently only
captures X/Twitter post trees (text + links + curated comments) to a JSONL
file. The user wants an agent right in the extension that reasons over the
pending capture — tweet content and urls — before it is saved, so posts are
saved with more context. The full pi SDK (createAgentSession, custom tools,
streaming events) was available as a reuse candidate.

### Problem

Where should the agent run? The browser sandbox cannot host the pi SDK (no
Node runtime, no filesystem, ephemeral MV3 service workers, restricted
networking). An OpenRouter API key must never live inside a browser extension.
The user explicitly asked whether pi could be embedded inside the extension.

### Alternatives

- **Embed pi inside the extension** — rejected: Chrome MV3 is not a Node
  runtime; createAgentSession needs fs, child processes, session persistence;
  the service worker is killed after ~30s idle; url-fetching from the browser
  hits CORS.
- **pi RPC mode (`pi --mode rpc` + thin bridge)** — viable and evaluated in
  depth: JSONL over stdin/stdout, reuses the real pi CLI/config, decoupled
  upgrades. Rejected in favour of the SDK because the extension needs a
  localhost socket regardless, and the SDK keeps tools in-code (type-safe
  `defineTool`), one process, no subprocess/IPC framing to maintain.
- **Custom agent loop written from scratch** — rejected: duplicates what pi
  already provides (reasoning, tool loop, streaming, compaction/retry).

### Decision

Run the agent as a **local Node service embedding the pi SDK**:
`capture/agent-service/` exposes a WebSocket on `127.0.0.1:8766`; the side
panel connects to it, sends the pending capture tree + the user's prompt, and
streams answers rendered live. The agent session is created per ask with
`createAgentSession` (in-memory, custom `fetch_url` tool, no coding tools),
persisted to disk on completion. The Python capture server stays unchanged for
saves, and later gains the read/search API.

### Rationale

The extension is UI-only either way; the SDK gives the full pi agent
capability in one Node process with in-code typed tools, no subprocess to
manage, and direct `session.subscribe()` streaming. The browser sandbox makes
"pi inside the extension" impossible, so host-side reasoning with an
extension UI is the correct shape.

### Consequences

- A new `capture/agent-service/` (Node + pi SDK) is added; the extension
  manifest gains a `ws://127.0.0.1:8766` connect permission.
- pi remains a bundled dependency of that service; upgrades require a service
  rebuild (unlike RPC mode). Accepted trade-off.
- The side panel becomes the agent UI: pending tree + prompt in, streaming
  reasoning out.

### Revision triggers

- If pi is ever distributed as a standalone service that should not be
  re-bundled, or the service needs process isolation, re-evaluate the RPC
  route (same architecture, thinner glue).
- If the browser sandbox gains Node capabilities (unlikely), revisit "agent
  in the extension".