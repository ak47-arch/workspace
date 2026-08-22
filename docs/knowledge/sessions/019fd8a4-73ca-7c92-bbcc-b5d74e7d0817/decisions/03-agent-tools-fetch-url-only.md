## Decision: Agent tools restricted to fetch_url for v1 — no bash, no web search

**Status**: accepted
**Date**: 2026-08-08 21:43
**Task**: [extension-inline-agent](../../../../tasks/extension-inline-agent.md)
**Project**: feed_analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The agent gets exactly one custom tool, fetch_url, implemented with defineTool in the agent service: fetch-and-read a url (server-side, so no browser CORS).

### Context

The agent reasons over a pending capture: tweet text, urls (resolved out of
t.co), and recursive comment nodes. The user wants the agent to "hit those
urls" — fetch and read the links present in the capture. The pi SDK sessions
normally ship with coding tools (read, write, edit, bash, grep, ...).

### Problem

What can the agent do? Which tools are safe and in scope?

### Alternatives

- **Full pi coding toolset (incl. bash)** — rejected by the user ("the pi
  agent will not have bash tool"). Shell access from a reasoning loop over
  web content is unbounded and unnecessary.
- **General web search tool** — rejected by the user for v1 ("restrict it to
  the url"): the agent should reason over *this capture's* urls, not roam the
  whole web. Search beyond the capture is a possible later extension.
- **Fetch all urls up front** — rejected: the agent should decide which urls
  are relevant to the user's question and fetch those, as part of reasoning.

### Decision

The agent gets exactly one custom tool, `fetch_url`, implemented with
`defineTool` in the agent service: fetch-and-read a url (server-side, so no
browser CORS). The session is created with coding tools stripped
(`tools: ["fetch_url"]` + custom tool only). The agent decides which of the
capture's urls to fetch. No bash, no generic web search, no browser control
(see separate decision).

### Rationale

Bounded and predictable: the agent's reach is limited to content the user has
already curated into the capture, plus the urls inside it. Server-side
fetching also avoids CORS entirely.

### Consequences

- The agent cannot be asked to do arbitrary tasks (file ops, shell) — it is a
  reasoning/analysis agent over capture content only.
- `fetch_url` needs sane limits (size caps, timeout) to protect the service
  from huge pages.

### Revision triggers

- When the user wants general research (search beyond the tweet), add a
  `web_search` tool.
- If the agent needs the live page (e.g. expanding the thread), that is the
  deferred browser-control capability, not an extension of this decision.
