# Code Review

- Reviewed: ak47-arch/feed_analyser#1 (repo: feed_analyser, PR #1)
- Task: extension-inline-agent · PRD: docs/prd-queue/2026-08-08-extension-inline-agent.md · Review session: f8cb56ec-d6f6-4641-bf7f-126c039c3879
- Base: 1771fdce79f46b39b307ed6caa2d0c836a3c6108 → Head: 24e60a87a6926724c2ef6037d9daf87eaea6ecf7

## Verdict

REQUEST_CHANGES — one blocking correctness/robustness gap: on a fresh checkout (no `data/` dir ever created) a plain Save with the agent unavailable raises an unhandled `FileNotFoundError` → HTTP 500, breaking US5's "saving still works as today" guarantee. Everything else (all 7 stories, verification commands, scope, no secrets) checks out.

## Verification results

| PRD command | Result | Evidence |
|---|---|---|
| `cd capture/server && python -m pytest tests/` | **RAN — 20 passed** | Ran against a /tmp-installed dep tree (fastapi 0.141, httpx, pytest 9.1) via `PYTHONPATH=/tmp/pyreqs python3 -m pytest tests/ -q` in the worktree (no `.venv` present; deps never written into the repo). `20 passed` — 10 original capture tests + 4 agent-envelope + 6 search. |
| Agent service smoke (mock, no key) `AGENT_MOCK=1 node server.js` + `node test/smoke.mjs` | **RAN — SMOKE PASS** | Copied `agent-service` to /tmp (avoid writing node_modules into repo), `npm install`, ran `AGENT_MOCK=1 node server.js` on :18766 → `SMOKE PASS: ask -> deltas -> settled -> follow_up -> settled; evidence persisted`; evidence file written at `data/sessions/<uuid>/session.jsonl` with `"type":"session"` header. |
| Agent service `node server.js` real inference | **DEFERRED** | Needs `OPENROUTER_API_KEY` + live OpenRouter network creds not present in sandbox. Implementer's live-run claim (71 deltas, fetch_url used) recorded but not reproducible here — left for UAT. |
| `fetch_url` caps `node test/fetch_url.test.mjs` | **RAN — PASS** | `fetch_url caps: PASS (invalid url, protocol, plain text, html strip, body cap)` — timeout/size/public-protocol guards exercised against local test servers. |
| `bin/rebuild-index.py` + `curl /search` | **RAN — PASS** | `python3 bin/rebuild-index.py --artefacts /tmp/fixture/artefacts.jsonl --index /tmp/fixture/index.db --verbose` → `Indexed 3 capture(s)`. `/search` via TestClient over the fixture: `q=arxiv`→1 with agent envelope, `q=github`→1 (url path component), `author=@alice` filter→1, `since` exclusion→0, `rank:true`. Envelope validation: missing sessionFile→400, valid→200. |
| Extension JS syntax `node --check` | **RAN — PASS** | `sidepanel.js OK`, `agent-client.js OK`. |
| Full browser panel e2e (ask→stream→save→search→open session) | **DEFERRED** | Requires a live Chrome/Chromium side panel on x.com + user's key/machine. Handed to UAT. |

## Story-by-story

- [PASS] US1 ask→streamed answer — `sidepanel.html` Ask fieldset; `sidepanel.js` `askAgent`/`appendDeliveredText`; `agent-client.js` WS client; `agent-service/server.js` streams `{type:"delta",text}`. Verified by mock smoke (deltas before settled) + real-run claim.
- [PASS] US2 agent fetches/reads capture urls — `tools/fetch_url.js` (only tool, server-side, ~1 MB / 30 s caps, html→text, non-http reject); `agent.js` tools=[fetch_url], minimalResourceLoader strips all others. `fetch_url.test.mjs` PASS.
- [PASS] US3 follow-ups keep context — `agent-service/server.js` per-`captureId` in-memory handle; `follow_up` reuses `AgentSession`; mock smoke does ask→settled→follow_up→settled; persisted session.jsonl holds both turns.
- [PASS] US4 save stores tree + agent evidence envelope — `persist.js` writes pi-native v3 `session.jsonl` to `data/sessions/<uuid>/`; `server.js` sends `settled` w/ sessionId/sessionFile/model/cost; `sidepanel.js` stashes envelope and sets `artefact.agent` in `submit()`; `server.py` validates + persists envelope verbatim. Envelope tests pass.
- [FAIL] US5 agent unavailable → save still works — UI state (`agent-unavailable` banner, `onDown`/`onError`) present, and save-without-agent POST itself has no envelope requirement. **BUT** on a fresh checkout where `data/` was never created (and nothing creates it before the first save), `append_artefact` raises `FileNotFoundError` → 500, so saving does NOT actually work in that scenario. Blocking (see Findings).
- [PASS] US6 search saved captures, relevance-ranked, link to evidence — `index.py` (FTS5 BM25), `bin/rebuild-index.py`, `server.py` `GET /search` (`{items,total,rank}`) returning the `agent` envelope (→ sessionFile). Verified rebuild + `/search` and search test-suite (keyword/author/url/since/limit).
- [PASS] US7 existing capture flow unchanged — `content.js`/`background.js` untouched; hover pill/notes tree renderer untouched; no-envelope `/api/capture` path byte-compatible (full original 10-test regression passes). Minor additive agent UI only.

## Deterministic checks

- [PASS] D1 PR metadata sane — PR head `factory/extension-inline-agent`, commit `implementer(...) [factory]`; base 1771fdc / head 24e60a8 refs resolvable; `base...head` diff non-empty, 23 files, all under `capture/` + repo `.gitignore`/`run-server.sh`.
- [PASS] D2 Worktree clean / read-only — `git status` → `HEAD detached at 24e60a8`, `nothing to commit, working tree clean`. Reviewer made no repo writes (verification deps installed only under /tmp).
- [PASS] D3 Scope containment — every changed path is within the PRD scope or explicit doc/dev support: `capture/README.md`, `agent-service/README.md`, `agent-service/.gitignore`, `package-lock.json`, `test/smoke.mjs`, `test/fetch_url.test.mjs`, `serialize.js` (extra informational/tooling consistent with PRD Testing decisions + storage relocation). `run-server.sh` + `.gitignore` changes explicitly implied by PRD data-model section. No unrelated refactors.
- [PASS] D4 Scope ⊆ PRD file-map — all PRD file-tree entries present. Noted deltas: `tools/fetch_url.ts` delivered as `.js` (repo is ESM/JS, no TS — documented decision), `data/artefacts.jsonl` "move" is gitignored/untracked so handled at deploy/UAT (upgrade note in report), `data/sessions/` + `index.db` derived+gitignored.
- [PASS] D5 Story → diff coverage — every story maps to concrete hunks/files (above); no capability present that no story asks for.
- [PASS] D6 No secrets / stray deps — no committed keys (scanned for `sk-*`, `AIza`, inline api keys; `OPENROUTER_API_KEY` only read from env, in-memory AuthStorage). Deps only `@earendil-works/pi-coding-agent` + `ws` (both PRD-mandated).
- [PASS] D7 Implementer report ↔ diff — story claims match files; verification numbers reproduce (20 passed, SMOKE PASS, fetch_url PASS, node --check OK); only "real OpenRouter run" not reproducible in-sandbox (recorded as deferred). Nothing silently dropped.

## Judgment checks

- [PASS] J1 Story intent — observable behavior implied by each story works from the diff and the run verification, with the US5 exception documented under blocking.
- [PASS] J2 PRD-decision conformance — Decisions 01–06 honored (pi SDK WS service :8766; OpenRouter server-side key; fetch_url-only tools; artefact+session evidence model; plain-files+FTS5; browser control deferred). Documented deviations (`fetch_url.js`, `deepseek/deepseek-v4-flash` alias + temperature not force-injected, in-memory auth, `/search` auto-rebuild-of-missing-index) are recorded in the implementer decision file 01 with rationale and are overridable via `AGENT_MODEL`/`models.json`. Advisory-only divergence: search auto-build is a small convenience outside the strictt PRD "manual/cron" wording but harmless (index is derived).
- [FAIL] J3 Edge/error paths — fetch caps, invalid-FTS queries (400), agent-unavailable/reconnect handled well; **missing `data/` dir on first plain save → unhandled 500** (blocking, see Findings).
- [PASS] J4 Ponytail review — see Advisory findings + Ponytail debt below (skills not mounted in this container; pass applied manually per the documented format/methodology).
- [PASS] J5 UAT gaps — precise list below.

## Findings

### Blocking (→ REQUEST_CHANGES)
- `capture/server/server.py:60` (`append_artefact`) — `target.open("a")` never creates the parent `data/` dir. On a fresh checkout `data/` is gitignored and untracked, `run-server.sh` does not mkdir it, and only `index.py.rebuild()` (triggered by `/search`) or the agent-service `persistSession` create it. So the first **plain Save with the agent unavailable** — exactly the US5 scenario ("agent unavailable … saving still works as today") — raises an unhandled `FileNotFoundError` → HTTP 500 (confirmed by direct POST to `/api/capture` with a missing parent dir). This breaks a core story's guarantee in a realistic first-run path. Fix: `target.parent.mkdir(parents=True, exist_ok=True)` before opening (or mkdir `data/` at startup), matching how `index.py.rebuild` already does it.

### Advisory (consider / over-engineering)
- `capture/extension/sidepanel.js:237` — `agentAskBtn.disabled = agentBusy || !!(current && current.tweet_url) === false;` has inverted/ambiguous precedence (works, but reads wrong): `!!(current && current.tweet_url) === false`. `native` — write the positive form, e.g. `agentBusy || !(current && current.tweet_url)`.
- `capture/server/index.py` (build_fts_query, ~70 lines) — a hand-rolled FTS5 MATCH translator for AND/OR/phrases/`author:` qualifiers; justified by the PRD's search criteria but the most complex new member. `shrink` — acceptable as-is; could lean on the PRD's simpler "quoted phrase + AND" if the qualifier grammar is trimmed.
- `capture/server/index.py:230` — `total = len(rows)` is computed after `LIMIT`, so `/search.total` reflects the capped page, not the true total. `native` — count via `COUNT(*)` before the LIMIT if total matters to consumers.
- `capture/agent-service/server.js` (`disposeForSocket` + panel `askAgent` sending `messages:[]`) — an in-memory session is dropped on socket close and the panel does not pass its `agentMessages` transcript on a reconnect `ask`, so a follow-up after a mid-capture service restart/reconnect loses capture context (new session). Edge case; `shrink`/document — acceptable for v1 UAT single-session flow but worth a note or wiring `messages` through on reconnect.

## Ponytail debt (harvested from changed files)
- No `ponytail:` shortcut markers found in the changed files (`grep -rn ponytail capture/` → none). No pre-existing debt markers to carry forward.

## UAT hand-off list
1. `cd capture/agent-service && npm install`, run `OPENROUTER_API_KEY=… node server.js` (→ ws://127.0.0.1:8766); confirm a real ask streams, uses `fetch_url` on a linked url, and `.then` settle returns model+cost.
2. Load the unpacked extension on x.com; capture a tweet w/ comments + links; ask → stream → follow-up → "fetched <url>" tool feedback.
3. Click **Save** on a machine where `capture/server/data/` does NOT exist yet and the agent service is stopped — **confirm save succeeds** (this is the blocking fix to validate after applied). Then repeat Save with the agent running and verify a line lands in `data/artefacts.jsonl` with the `agent` envelope and `data/sessions/<uuid>/session.jsonl` exists and opens.
4. Search it: `cd capture/server && .venv/bin/python bin/rebuild-index.py` then `curl "http://127.0.0.1:8765/search?q=<term>"` (content / author / url) — confirm relevance ordering and the returned `agent.sessionFile` opens the evidence.
5. Upgrade check: if you already have captures at `capture/server/artefacts.jsonl`, move the file once to `capture/server/data/artefacts.jsonl` (no re-capture); confirm `CAPTURE_DATA` still overrides.
6. Confirm the model/pricing decision: default `deepseek/deepseek-v4-flash` (alias) — override with `AGENT_MODEL` for the dated `-0731` id if you want it pinned; confirm `temperature ~0.2` intent is acceptable as-is (pi controls inference temp internally).
7. Approve the PRD file-map deltas: `fetch_url.js` (not `.ts`), search auto-rebuild-on-missing-index, in-memory auth (no `auth.json`/`models.json` written).
