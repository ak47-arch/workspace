# Implementation Report — extension-inline-agent

**Task**: extension-inline-agent
**Session**: 60c0c537-b9c7-4c4c-8b8a-0be438950151
**Date**: 2026-08-11
**PRD**: `docs/prd-queue/2026-08-08-extension-inline-agent.md`

All 7 user stories implemented. Worktree: `/sandbox/worktree` (host owns git; no
git commands run here). Below: per-story evidence, then verification results,
then the UAT hand-off list, then emerged decisions.

---

## Stories

### 1. Ask a question → agent answer streams into the panel — DONE
- `capture/extension/sidepanel.html` — added an **Ask** fieldset (chat thread,
  text input, Ask/Stop buttons, unavailable banner).
- `capture/extension/sidepanel.js` — `askAgent()`/`followUpAgent()`, streaming
  render via `appendDeliveredText`, agent byte-by-byte deltas appended live.
- `capture/extension/agent-client.js` (NEW) — thin W3C WebSocket client with
  reconnect/backoff; emits `delta`/`tool`/`settled`/`error`/`ready`.
- `capture/agent-service/server.js` — WebSocket on `127.0.0.1:8766`; on `ask`
  streams `{type:"delta", text}` events; `capture/agent-service/agent.js`
  bridges `session.subscribe` → `message_update.text_delta` → ws delta.
- **Verified**: `node test/smoke.mjs` (mock) — ask → several `delta` → `settled`
  (`SMOKE PASS`); a real OpenRouter run streamed 71 deltas.

### 2. Agent fetches + reads urls in the capture — DONE
- `capture/agent-service/tools/fetch_url.js` (NEW) — the single custom tool,
  server-side fetch with ~1 MB body cap + 30 s timeout, HTML→text, non-HTTP
  rejection. Registered as the only tool (`tools:["fetch_url"]`,
  `customTools:[fetchUrlTool]`), coding tools stripped (Decision 03).
- **Verified**: `node test/fetch_url.test.mjs` (`fetch_url caps: PASS` — invalid
  url, unsupported protocol, plain text, HTML strip, body cap) and real-mode run
  showed repeated `{type:"tool", tool:"fetch_url", arg:…}` events and `toolResult`
  entries persisted.

### 3. Follow-up questions keep capture context across turns — DONE
- `capture/agent-service/server.js` keeps a per-`captureId` in-memory session
  handle; `follow_up` reuses the same `AgentSession.`
- `capture/agent-service/agent.js` `followUp()` → `session.followUp(prompt)`;
  context retained via the live session.
- **Verified**: mock smoke performs `ask → settled → follow_up → settled` on the
  same `captureId` (`SMOKE PASS`); the persisted session.jsonl contains both
  turns in one linear conversation.

### 4. Save stores tree as before + conversation saved as evidence linked by `agent` envelope — DONE
- `capture/agent-service/persist.js` (NEW) — writes the full conversation as a
  **pi-native v3 `session.jsonl`** to `data/sessions/<uuid>/session.jsonl`
  (header + `message` entries with `id`/`parentId`, same format the factory KB
  and `extract-context` consume); returns `{sessionId, sessionFile}` envelope.
- `capture/agent-service/server.js` `onSettled` → persist + send `settled` with
  `sessionId/sessionFile/model/cost`.
- `capture/server/server.py` — validates an optional root `agent` envelope
  (must carry `sessionId`+`sessionFile`, else 400) and persists it verbatim on
  the artefact line.
- `capture/extension/sidepanel.js` — stashes the envelope on `settled` and
  attaches it (`artefact.agent = agentEnvelope`) in `submit()`.
- **Verified**: pytest envelope tests; smoke verifies the evidence file exists
  with a `session` header; real run produced a valid session.jsonl with
  `thinking`, `toolResult`, and assistant text entries.

### 5. Agent/OpenRouter unavailable → clear "agent unavailable"; saving still works — DONE
- `capture/extension/agent-client.js` — `onDown`/`onError` surface unreachability
  immediately; `capture/extension/sidepanel.js` shows the unavailable banner
  and keeps the Ask input usable but clearly dead; **Save is independent of the
  agent** (no envelope required).
- `capture/agent-service/server.js` — graceful `{type:"error", message:"Agent
  unavailable: …"}` on model/tool failure; never crashes.
- **Verified**: agent-service returns an error, not a crash, when inference is
  unavailable; `/api/capture` saves fine with no `agent` field (regression).

### 6. Search saved captures by content/author/url, relevance-ranked, link to evidence — DONE
- `capture/server/index.py` (NEW) — rebuildable SQLite + **FTS5 (BM25)** index;
  `CaptureIndex.rebuild()` / `search()`; urls tokenized so path components are
  searchable; `author`/`since`/`limit` filters.
- `capture/server/bin/rebuild-index.py` (NEW) — derives `data/index.db` from
  `data/artefacts.jsonl`.
- `capture/server/server.py` — `GET /search` read API returning
  `{items, total, rank:true}`; results carry the `agent` envelope (→
  `sessionFile`) linking evidence.
- **Verified**: pytest search e2e (keyword, author filter, url component,
  since filter, limit) and live `curl` (`arxiv`, `github`, `author=@alice`,
  `since`); rebuild-index reported "Indexed N capture(s)".

### 7. Existing capture flow unchanged — DONE
- The hover pill, Add/Remove comments, notes, and server error handling are
  untouched (`content.js`, `background.js` unchanged; `sidepanel.js` renderer
  untouched apart from additive agent UI).
- Save-without-agent stays byte-compatible (`/api/capture` logic unchanged for
  the no-envelope case).
- **Verified**: the full original `pytest` regression suite passes unchanged.

---

## Verification results

| Check | Command | Result |
|---|---|---|
| Python regression + new seams | `cd capture/server && .venv/bin/python -m pytest tests/ -q` | `20 passed` (10 original + 10 new) |
| Agent service smoke (mock, no key) | `AGENT_MOCK=1 node server.js` + `node test/smoke.mjs <ws-url>` | `SMOKE PASS`: ask→deltas→settled→follow_up→settled; evidence persisted |
| fetch_url caps | `node test/fetch_url.test.mjs` | `PASS` (invalid url, protocol, plain text, html strip, body cap) |
| Rebuild + search | `python bin/rebuild-index.py --verbose` then `curl /search?q=…` | Indexed; `/search` returned ranked hits, author/url/since filters OK; agent envelope linked in results |
| Real inference (OpenRouter) | `node server.js` + ask with a link | Agent used `fetch_url`, streamed deltas, persisted session with `thinking`+`toolResult`, returned model+cost; gracefully refused to fabricate when fetch failed |
| Extension JS syntax | `node --check sidepanel.js agent-client.js` | OK |

Not run in-sandbox (needs a browser + your key): the full end-to-end panel ask →
stream → save → search → open-session walkthrough. Left for UAT below.

## UAT hand-off list

1. `cd capture/agent-service && npm install`, then run it with your
   `OPENROUTER_API_KEY`: `OPENROUTER_API_KEY=… node server.js` (→ `ws://127.0.0.1:8766`).
2. Load the extension (unpacked `capture/extension/`); on x.com capture a tweet
   with comments/links; type a question in **Ask** and confirm the answer
   streams; ask a follow-up; confirm "fetched <url>" tool feedback.
3. Click **Save**; confirm a line lands in `capture/server/data/artefacts.jsonl`
   carrying the `agent` envelope and that
   `capture/server/data/sessions/<uuid>/session.jsonl` exists (open it — it is a
   pi-native v3 session file).
4. Search it: `cd capture/server && .venv/bin/python bin/rebuild-index.py` then
   `curl "http://127.0.0.1:8765/search?q=<term>"` (content / author / url).
5. Stop the agent service, Save again — the panel shows **agent unavailable**
   and the capture still saves as before.
6. **Upgrade note**: the artefacts file moved from
   `capture/server/artefacts.jsonl` → `capture/server/data/artefacts.jsonl`.
   If you already have captures in the old location, move the file once (no
   re-capture). `CAPTURE_DATA` still overrides it.
7. Model/pricing: default model is `deepseek/deepseek-v4-flash` (the built-in
   alias of the dated id noted in the PRD). Override with `AGENT_MODEL` if you
   want the dated variant. If OpenRouter's pricing for that id differs, update
   `capture/agent-service/models.mjs` (`DEFAULT_MODEL`) or supply a
   `models.json`; see decisions file.

## Emerged decisions

- `outbox/decisions/01-extension-inline-agent.md`
