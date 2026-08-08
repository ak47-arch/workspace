## Decision: Inference via OpenRouter; key stays server-side

**Status**: accepted
**Date**: 2026-08-08 21:43
**Task**: extension-inline-agent
**Project**: feed_analyser
**Session**: sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/session.jsonl

### Context

The capture instrument's agent needs LLM inference. The factory runs a local
inference server (`llm/` project, OpenAI-compatible on :8012). The user also
has an OpenRouter account already wired into pi (existing knowledge sessions
show provider `openrouter`, model `deepseek/deepseek-v4-flash`).

### Problem

Which inference backend, and where does the credential live?

### Alternatives

- **Local `llm/` server** — rejected by the user explicitly ("we wont be
  using llm/"). Adds a local model runtime dependency and model management
  overhead for a personal reasoning agent.
- **OpenRouter called from the browser extension** — rejected: the API key
  would be bundled into the extension and exposed; url fetching from browser
  faces CORS.

### Decision

Use **OpenRouter** as the provider, invoked from the local `capture/agent-service/`
(pi SDK `ModelRuntime`), with the key in the service's own environment
(`OPENROUTER_API_KEY`) — never in the browser. Default model
`deepseek/deepseek-v4-flash` with thinking on, low temperature (~0.2) for
analysis work.

### Rationale

Reuses the OpenRouter relationship pi already has, avoids running and
maintaining a second local model backend, and keeps the credential off the
client. OpenRouter is OpenAI-compatible, which pi supports natively.

### Consequences

- Remote inference cost per ask; an offline/no-key state means the agent
  feature is unavailable (graceful "agent unavailable" in the panel).
- The `llm/` project is not involved in capture.

### Revision triggers

- If local inference becomes desirable (privacy, offline), swap the pi
  provider to a local backend without touching panel/service contracts.