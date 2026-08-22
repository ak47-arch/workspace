# PRD: Extension Inline Agent — reason over captures, save enriched evidence

**Date**: 2026-08-08 21:50
**Status**: [Final](./manifest.json)
**Owner**: feed_analyser / capture instrument
**Task**: [extension-inline-agent](../tasks/extension-inline-agent.md)
**Session**: [session.jsonl](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/session.jsonl)
**Decisions**:
  - [01-pi-sdk-agent-service](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/01-pi-sdk-agent-service.md)
  - [02-openrouter-inference-server-side-key](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/02-openrouter-inference-server-side-key.md)
  - [03-agent-tools-fetch-url-only](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/03-agent-tools-fetch-url-only.md)
  - [04-artefact-session-evidence-model](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/04-artefact-session-evidence-model.md)
  - [05-twitter-kb-plain-files-fts5-read-api](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/05-twitter-kb-plain-files-fts5-read-api.md)
  - [06-browser-control-deferred](../knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/decisions/06-browser-control-deferred.md)
## Problem statement

The capture instrument saves X/Twitter posts (text + links + curated comment
nodes) as raw trees — the user's own curation of *what* deserves keeping, but
without any of their thinking about it. The collected content lacks context:
when a post is revisited months later, only the words survive, not why it
mattered, what it connects to, or what the linked material actually said. The
vision has always pointed here — captured content becomes raw material for
later tools — but until now analysis was explicitly out of scope.

Today the extension shows the pending capture (tweet text, all urls,
recursive comments) right before save — an ideal surface to reason *then and
there*, while the moment is fresh. Nothing in the current stack can do that:
the extension is a thin DOM scraper, the Python server is a dumb receiver to
JSONL, and no reasoning layer exists. The result is a growing flat file of
trees with no analysis attached, no search, and no clean seam for the
applications the user plans to build on top.

We now have the missing ingredient: the pi SDK (agent sessions, custom tools,
streaming) and an OpenRouter account. This task wires those together so the
user reasons with an agent over each pending capture, and saves a **richer,
self-contained artefact** that downstream apps can consume.

## Solution overview

An agent lives beside the capture flow. While a capture is in progress
(pending, not yet saved), the side panel gains an **Ask** interface: the user
asks a question about the tweet tree, and a pi agent running on the host
reasons over the capture — fetching and reading the urls inside it via a
single `fetch_url` tool — and streams an answer back into the panel, where
further follow-ups can continue the conversation. On Save, the capture is
persisted as before, now carrying an `agent` envelope that points at the full
conversation, which is written to disk as a pi-native `session.jsonl`
evidence file — the same format the factory knowledge base already uses.

The same corpus (trees + sessions) becomes a searchable, pluggable personal
knowledge base: plain files remain the source of truth, a rebuildable SQLite
FTS5 index powers relevance-ranked search, and the capture server exposes a
thin read API other applications consume. Browser control of the live x.com
page is deliberately deferred to a follow-on phase.

## User stories

1. As a user on x.com, when I have a pending capture in the side panel, I can
   type a question about the tweet (e.g. "summarise this post", "what is the
   core claim?") and see the agent's answer stream into the panel.
2. The agent can fetch and read any url present in the capture when it is
   relevant to my question (e.g. "summarise the article it links to").
3. I can ask follow-up questions in the same conversation; the agent keeps the
   capture context across turns.
4. When I click **Save**, the capture tree is stored exactly as before, and
   the full agent conversation is saved as evidence and linked from the
   artefact via an `agent` envelope.
5. If the agent service or OpenRouter is unavailable, the panel shows a clear
   "agent unavailable" state and saving still works as today.
6. After saving, I (or any downstream app) can search saved captures by
   content, author, or url and get relevance-ranked results; each result
   links to the underlying session evidence.
7. Nothing about the existing capture flow changes: hover pill, Add/Remove
   comments, notes, and server error handling all behave as before.

## Implementation decisions

- **Agent backend**: pi SDK (`createAgentSession`, `defineTool`,
  `session.subscribe`) embedded in a new local Node service
  `capture/agent-service/`, exposing a WebSocket on `127.0.0.1:8766`. Decision 01.
- **Inference**: OpenRouter via pi's `ModelRuntime`; key in the service's own
  env (`OPENROUTER_API_KEY`), never in the browser. Default model
  `deepseek/deepseek-v4-flash-0731` (the id recorded in the planning session;
  exact token pricing verified against OpenRouter at implementation time), thinking
  on, temperature ~0.2. Decision 02.
- **Tools**: exactly one custom tool, `fetch_url` (server-side, capped at
  ~1 MB response body / 30 s timeout). No
  bash, no coding tools, no web search in v1. The agent decides which urls to
  fetch. Decision 03.
- **Artefact model**: one artefact = tree line with `agent` envelope +
  `sessions/<uuid>/session.jsonl` full conversation as evidence (pi-native
  format). Answers are saved verbatim, not edited. Decision 04.
- **Context injection**: the pending tree (root + comments with text and
  urls) is serialized inline into the agent's first prompt.
- **Rendering**: token-by-token streaming via WebSocket; tool activity shown
  subtly ("fetched <url>").
- **KB store**: plain files as canonical truth; `bin/rebuild-index` derives a
  SQLite + FTS5 index (BM25); Python server exposes the read API. Decision 05.
- **No browser control** in this phase (deferred, same bridge later).
  Decision 06.

## Testing decisions

Seams, from highest to lowest:

- **Agent service API** (integration): the WebSocket request/response and
  stream contract is tested against a stubbed OpenRouter or recorded
  fixture — prompt in, `text_delta` events out, session.jsonl persisted.
- **`fetch_url` tool** (unit): caps (≈1 MB body / 30 s timeout, the agreed
  defaults), timeouts, non-HTTP handling, error text
  returned to the model.
- **Server read API + index** (integration): rebuild-index from a fixture
  corpus; `/search` returns ranked hits; artefact lines with an `agent`
  envelope parse and link to an existing session file.
- **Extension side panel** (manual, as today): ask → stream → save with
  envelope → artefact lands in JSONL and `sessions/<uuid>/session.jsonl`
  exists.
- **Regression**: existing `pytest` suite for `/api/capture` keeps passing;
  save-without-agent stays byte-compatible.

Concrete commands: `cd feed_analyser/capture/server && .venv/bin/python -m
pytest tests/` (regression + new seams); `node server.js` smoke check for the
agent service (an `ask` round-trip returns a `settled` event); `python
capture/server/bin/rebuild-index.py` followed by a `curl` of `/search`.

Done = UAT: an end-to-end capture with a multi-turn ask, save, search, and
opening the linked session evidence all work on the user's machine
(`run-server.sh`, extension side panel, `GET /search?q=<term>`).

## Out-of-scope

- **Browser control** (pi driving the live page via the extension) —
  follow-on phase on the same bridge.
- **General web search** beyond the capture's urls.
- **Editing / regenerating** a saved agent answer (evidence stays verbatim).
- **Vector/semantic search** — keyword/FTS5 only for now.
- **Auto-capture, engagement, media** — unchanged from capture v1 scope.
- **Image understanding** of the tweet media.

## Further notes

- Session files must be excluded from git (evidence is user data, like
  `artefacts.jsonl`).
- `fetch_url` needs size/time caps so one huge page cannot stall a session.
- The `agent` envelope carries model + cost metadata, useful for the training
  / RL evidence angle.
- **openwiki caveat**: `feed_analyser/openwiki/capture/{extension,server}.md`
  describe the archived legacy architecture (React src/, SQLite captures.db,
  /api/v1/capture) and are stale — code + this PRD are the authority;
  OpenWiki refresh is a follow-up.
- Storage layout (under `capture/server/data/`): `artefacts.jsonl` (moved
  from `server/`, existing file carried over), `sessions/<uuid>/session.jsonl`,
  `index.db` — mirroring the factory KB structure on purpose.

## Architecture

### System diagram

```
side panel (extension, sidepanel.js)
   │  pending tree + prompt (WebSocket)
   ▼
capture/agent-service/  (Node + pi SDK)   ws://127.0.0.1:8766
   │  createAgentSession (tools=[fetch_url], no coding tools)
   │  fetch_url tool: server-side HTTP (no CORS)
   │  ModelRuntime → OpenRouter (deepseek-v4-flash, thinking on)
   │  on settle: persist session.jsonl → data/sessions/<uuid>/
   └────────────► returns { sessionId, sessionFile } to panel

Python capture server (:8765, unchanged for capture)
   POST /api/capture  ← tree + optional agent envelope → artefacts.jsonl
   GET  /search       ← read API over index.db (SQLite FTS5, BM25)
     index.db ← bin/rebuild-index  ←- reads artefacts.jsonl

data/
   artefacts.jsonl        (tree lines, each may carry agent envelope)
   sessions/<uuid>/session.jsonl   (full pi conversation, evidence)
   index.db               (derived, rebuildable)
```

### Data flow (agent ask)

1. Panel holds pending tree `current` (root + children with tweet_text, links,
   notes). User types a question and hits Ask.
2. Panel opens WebSocket to the agent service (reconnect/backoff) and sends
   `{ type: "ask", capture: tree, messages: [...prior turns...], prompt }`.
3. Service creates an in-memory `AgentSession` (per ask, reused across turns
   of the same capture via a session handle keyed by capture id).
4. First turn: capture tree is serialized inline into the user prompt.
5. Agent reasons; when it decides a url matters it calls `fetch_url`; the
   service fetches server-side (size/time capped) and returns the text.
6. `text_delta` events are pushed over the WebSocket; panel renders live.
7. On `agent_settled`, the service serializes the session to
   `data/sessions/<uuid>/session.jsonl` and replies with
   `{ sessionId, sessionFile, model, cost }`.
8. Panel stashes the envelope on the pending capture (not saved yet).
9. On Save, the panel POSTs the tree + envelope to `/api/capture` (unchanged
   route; server validates and appends the line).

### Endpoint contracts

Agent service (WebSocket, JSON messages):

```json
// panel → service
{ "type": "ask", "captureId": "c1", "tree": {…recursive node…},
  "messages": [{ "role": "user", "content": "…" }] }
{ "type": "follow_up", "captureId": "c1", "prompt": "…" }
{ "type": "abort", "captureId": "c1" }

// service → panel (events)
{ "type": "delta", "captureId": "c1", "text": "…" }
{ "type": "tool", "captureId": "c1", "tool": "fetch_url", "arg": "https://…" }
{ "type": "settled", "captureId": "c1",
  "sessionId": "<uuid>", "sessionFile": "sessions/<uuid>/session.jsonl",
  "model": "deepseek/deepseek-v4-flash", "cost": 0.042 }
{ "type": "error", "captureId": "c1", "message": "…" }
```

Capture server (new route):

```text
GET /search?q=arxiv&author=%40user&since=…&limit=50
→ { "items": [ { "id", "tweet_url", "author", "tweet_text", "links",
    "timestamp", "agent": { "sessionId", "sessionFile", "model",
    "capturedAt" } } ], "total": n, "rank": true }
```

FTS5-backed: `MATCH` accepts AND/OR, phrases, `author:` column qualifiers;
ordered by `bm25()`.

### Data model changes

- `artefacts.jsonl` line: existing recursive node tree, plus optional
  `agent` field on the root node:
  ```json
  { "tweet_url": "…", "author": "…", "tweet_text": "…", "links": […],
    "notes": "…", "children": […],
    "agent": { "sessionId": "<uuid>", "sessionFile": "sessions/<uuid>/session.jsonl",
                "prompt": "…", "model": "deepseek/deepseek-v4-flash",
                "capturedAt": "2026-08-08T…Z", "cost": 0.042 } }
  ```
- `sessions/<uuid>/session.jsonl`: pi-native v3 session file (evidence).
- **Storage relocation (explicit)**: `artefacts.jsonl` moves from
  `capture/server/artefacts.jsonl` to `capture/server/data/artefacts.jsonl`.
  The existing file is carried over on upgrade (no re-capture). `server.py`
  `DEFAULT_DATA_PATH` becomes `Path(__file__).resolve().parent / "data" /
  "artefacts.jsonl"`; `run-server.sh`'s documented default follows;
  `CAPTURE_DATA` override remains honored. The `.gitignore` rule moves with
  the file. `bin/rebuild-index.py` reads `data/artefacts.jsonl` — a single
  store matters: two paths would mean `/search` misses freshly saved captures.
- **Agent envelope validation**: when `agent` is present, it must carry
  `sessionId` + `sessionFile` (server returns 400 otherwise). The server does
  NOT verify the session file exists at save time — session persistence is
  the agent service's contract, and capture must succeed even if an envelope's
  session is later relocated.
- `index.db`: `captures` table (id, tweet_url, author, tweet_text, links JSON,
  timestamp, agent envelope JSON) + FTS5 virtual table; url column tokenized
  to preserve path components (custom tokenizer or `url` column).
- `.gitignore`: `capture/server/data/artefacts.jsonl`,
  `capture/server/data/sessions/`, `capture/server/data/index.db` (derived +
  user data).

## Program Design

### File-tree diff

```
capture/
  extension/
    manifest.json          { +"ws://127.0.0.1:8766/*" host_permissions }
    sidepanel.html         { + agent panel region: chat thread + input }
    sidepanel.js           { + ask/follow-up/abort, stream render, envelope stash,
                                include agent envelope on save } (moderate expansion)
    agent-client.js        (NEW) thin WebSocket client: connect, send, emit deltas,
                                reconnect/backoff, expose onmessage
  agent-service/           (NEW, Node + pi SDK)
    package.json           { deps: @earendil-works/pi-coding-agent, ws }
    server.js              { ws server on 8766, routes ask/follow_up/abort, holds
                                per-capture session handles }
    agent.js               { createAgentSession(cwd, inMemory, tools=[fetch_url]),
                                session.subscribe → delta events, settle → persist }
    tools/fetch_url.ts     { defineTool fetch_url: size/time caps, returns text }
    persist.js             { write session.jsonl to data/sessions/<uuid>/, return envelope }
    models.mjs             { ModelRuntime, OpenRouter provider, deepseek-v4-flash }
  server/
    server.py              { + GET /search (FTS5 read API); + agent envelope
                                validation on /api/capture;
                                DEFAULT_DATA_PATH → data/artefacts.jsonl }
    index.py               (NEW) SQLite + FTS5 schema, insert/query helpers
    bin/rebuild-index.py   (NEW) load data/artefacts.jsonl → data/index.db
    data/
      artefacts.jsonl      (MOVED from server/artefacts.jsonl — carry over the
                                existing file; .gitignore rule follows)
      sessions/            { <uuid>/session.jsonl (evidence; gitignored) }
      index.db             (derived; gitignored; rebuildable)
    tests/test_capture.py  { + envelope validation, + search e2e }
```

### Call-stack trees

Agent ask (service side):

```
ws.onMessage(ask)
  → AgentService.ask(captureId, tree, prompt)
    → getOrCreateSession(captureId)          // in-memory AgentSession
    → session.prompt(serializeTree(tree) + prompt)
    → session.subscribe(event)
        event.message_update.text_delta  → ws.send({type:"delta", text})
        event.tool_execution_start      → ws.send({type:"tool", arg})
        event.agent_settled             → persistSession() → ws.send({type:"settled"})
    → fetch_url tool.execute(params)
        → fetchWithCaps(params.url)      // size, timeout
        → return { content:[{type:"text", text}] }
```

Search (server side):

```
GET /search
  → parse q, author, since, limit
  → index.search(q, filters)             // FTS5 MATCH + bm25() ORDER BY rank
  → return { items, total }
```

### Key types and signatures

```typescript
// agent-service/ws protocol
type ToService = { type:"ask"|"follow_up"|"abort"; captureId:string;
                   tree?: NodeTree; messages?: Msg[]; prompt?: string };
type FromService = { type:"delta"; captureId:string; text:string }
                 | { type:"tool"; captureId:string; tool:"fetch_url"; arg:string }
                 | { type:"settled"; captureId:string; sessionId:string;
                     sessionFile:string; model:string; cost?:number }
                 | { type:"error"; captureId:string; message:string };

// domain (shared shape)
type NodeTree = { tweet_url:string; author?:string; tweet_text?:string;
                  links?:string[]; parent_url?:string|null; notes?:string;
                  children?: NodeTree[] };
type AgentEnvelope = { sessionId:string; sessionFile:string; prompt?:string;
                       model:string; capturedAt:string; cost?:number };

// tools/fetch_url.ts
defineTool({ name:"fetch_url", parameters:{ url:{ type:"string" } },
             execute: (id, {url}) => Promise<ToolResult> });

// server/index.py
class CaptureIndex:
    def rebuild(self, artefacts_path: Path) -> None
    def search(self, q: str, author: str|None, since: datetime|None,
               limit: int) -> list[dict]
```

### Build / run notes

- `capture/agent-service/`: `npm install`, env `OPENROUTER_API_KEY`; run
  `node server.js` → `ws://127.0.0.1:8766`.
- `bin/rebuild-index.py` runs after captures change (manual or cron) to
  refresh `index.db`; it is safe to delete/rebuild (derived).
- Restart the Python server after schema changes (existing convention).