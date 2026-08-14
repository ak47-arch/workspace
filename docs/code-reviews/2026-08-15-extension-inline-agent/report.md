# Code Review

- Reviewed: ak47-arch/feed_analyser#1 (repo: feed_analyser, PR #1)
- Task: extension-inline-agent · PRD: docs/prd-queue/2026-08-08-extension-inline-agent.md · Review session: 6f5b0d44-d1a3-41f5-b1f9-f4f1202bf1c1
- Base: 1771fdce79f46b39b307ed6caa2d0c836a3c6108 → Head: 93306541dfcbe6218d40d2b8a4bc9afc4e294ab1

This is the **re-review of revision 1** (head includes the implementer's blocking-fix commit `9330654` on top of the original `24e60a8`). The single blocking finding from the prior review (US5 — missing `data/` dir on first plain save → HTTP 500) is confirmed resolved; everything else is unchanged and re-verified.

## Verdict

APPROVE — the prior blocking US5 defect (unhandled `FileNotFoundError` on a fresh-checkout plain save) is fixed and verified both by a new regression test (21 passed) and by a live HTTP POST returning 200 while creating `data/` + the artefact file. All 7 stories, all deterministic checks, and all runnable verification commands pass; only real OpenRouter inference + the browser side-panel e2e remain deferred to UAT (need the user's key + live x.com panel). Remaining findings are advisory/non-blocking.

## Verification results

| PRD command | Result | Evidence |
|---|---|---|
| `cd capture/server && python -m pytest tests/` | **RAN — 21 passed** | No `.venv` in worktree; ran `PYTHONPATH=/tmp/pyreqs python3 -m pytest tests/ -q` (deps installed only to `/tmp/pyreqs`, never into the repo): `21 passed, 1 warning` — 10 original capture + 4 agent-envelope + 6 search + **1 new US5 regression** (`test_save_creates_missing_data_dir`). |
| US5 live runtime check (fresh, non-existent `data/`, plain save) | **RAN — PASS** | Started uvicorn on :8799 with `CAPTURE_DATA=/tmp/us5b_*/deep/data/artefacts.jsonl`, `POST /api/capture` → **HTTP 200** `{"status":"saved",...}`; `deep/data/` dir and `artefacts.jsonl` both created. This is the exact scenario the prior review reproduced as a 500. |
| Agent service smoke `AGENT_MOCK=1 node server.js` + `node test/smoke.mjs` | **RAN — SMOKE PASS** | Copied `agent-service` to `/tmp`, `npm install`, ran MOCK on :18766 → `SMOKE PASS: ask -> deltas -> settled -> follow_up -> settled; evidence persisted.` Evidence written at `/tmp/agent-evidence/sessions/<uuid>/session.jsonl` with `"type":"session","version":3` header. |
| Agent service real inference | **DEFERRED** | Requires `OPENROUTER_API_KEY` + live OpenRouter network creds absent from sandbox. Left for UAT. |
| `fetch_url` caps `node test/fetch_url.test.mjs` | **RAN — PASS** | `fetch_url caps: PASS (invalid url, protocol, plain text, html strip, body cap)` — protocol guard, 1 MB body cap, timeout path exercised against local test servers. |
| `bin/rebuild-index.py` + `curl /search` | **RAN — PASS** | `python3 bin/rebuild-index.py --artefacts /tmp/rb_105/artefacts.jsonl --index /tmp/rb_105/index.db --verbose` → `Indexed 3 capture(s)`. `/search` via TestClient: `q=arxiv`→1, `q=github`→1 (url path component), `q=paper`+since=08-02→0, author filter `@alice`→1, `rank:true`, and returned `agent.sessionFile`. Envelope validation covered in suite. |
| Extension JS syntax `node --check` | **RAN — PASS** | `sidepanel.js OK`, `agent-client.js OK`; all agent-service files (`server/agent/persist/models/serialize/tools`) pass `node --check`. |
| Full browser panel e2e (ask→stream→save→search→open session) | **DEFERRED** | Requires a live Chrome/Chromium side panel on x.com + user's key/machine. Handed to UAT. |

## Story-by-story

- [PASS] US1 ask → streamed answer — `sidepanel.html` Ask fieldset; `sidepanel.js` `askAgent`/`appendDeliveredText`; `agent-client.js` WS client (reconnect/backoff); `agent-service/server.js` streams `{type:"delta",text}`. Mock smoke produced deltas before `settled`.
- [PASS] US2 agent fetches/reads capture urls — `tools/fetch_url.js` (only tool via `tools:["fetch_url"]` + `minimalResourceLoader` stripping all others), server-side, ~1 MB / 30 s caps, html→text, non-http reject. `fetch_url.test.mjs` PASS.
- [PASS] US3 follow-up keeps context — per-`captureId` in-memory handle in `server.js`; `follow_up` reuses the same `AgentSession`; mock smoke does ask→settled→follow_up→settled; persisted session.jsonl holds both turns.
- [PASS] US4 save stores tree + agent evidence envelope — `persist.js` writes pi-native v3 `session.jsonl` to `data/sessions/<uuid>/`; `settled` returns sessionId/sessionFile/model/cost; `sidepanel.js` stashes `agentEnvelope` and sets `artefact.agent` in `submit()`; `server.py` validates (`sessionId`+`sessionFile`) and persists verbatim. Envelope tests pass; smoke verified the evidence file exists + header.
- [PASS] US5 agent unavailable → save still works — **fixed.** UI states (`agent-unavailable` banner, `onDown`/`onError`) present, save-without-agent has no envelope requirement, and `append_artefact` now `target.parent.mkdir(parents=True, exist_ok=True)` so a fresh-checkout plain save no longer 500s. Verified by new test + live 200 POST (above).
- [PASS] US6 search saved captures, relevance-ranked, link to evidence — `index.py` (FTS5 BM25, `bm25(captures_fts,5,1,1,1)`), `bin/rebuild-index.py`, `server.py` `GET /search` (`{items,total,rank}`) returning the `agent` envelope → `sessionFile`. Rebuild + `/search` and search suite (keyword/author/url/since/limit) pass.
- [PASS] US7 existing capture flow unchanged — `content.js`/`background.js` untouched; hover pill/notes/tree renderer untouched; no-envelope `/api/capture` path byte-compatible (10 original tests pass). Agent UI purely additive.

## Deterministic checks

- [PASS] D1 PR metadata sane — head `9330654` on `factory/extension-inline-agent`, commits `implementer(extension-inline-agent): … [factory]`; base 1771fdc / head 9330654 resolvable; `base...head` diff non-empty, 23 files, all under `capture/` + repo `.gitignore`/`run-server.sh`.
- [PASS] D2 Worktree clean / read-only — `git status` → `HEAD detached at 9330654`, `nothing to commit, working tree clean`; reviewer made zero repo writes (all verification deps/modules under `/tmp`).
- [PASS] D3 Scope containment — every changed path falls within the PRD file-tree diff or its explicit doc/dev support (`capture/README.md`, `agent-service/README.md`, `.gitignore`, `package.json`/`package-lock.json`, `test/smoke.mjs`, `test/fetch_url.test.mjs`, `serialize.js` — extra informational/tooling consistent with the PRD's storage relocation + Testing decisions). `run-server.sh` + `.gitignore` changes explicitly implied by the PRD Data-model section. Only trivial hygiene additions in-scope (`venv2/`, `.pytest_cache/` in the same in-scope `.gitignore`). No unrelated refactors.
- [PASS] D4 Scope ⊆ PRD file-map — all PRD file-tree entries present. Documented deltas carried from the original review: `tools/fetch_url.ts` delivered as `.js` (repo is ESM/JS, no TS — recorded decision); `data/artefacts.jsonl` "move" is gitignored/untracked so handled at deploy/UAT (upgrade note in reports); `data/sessions/` + `index.db` derived + gitignored.
- [PASS] D5 Story → diff coverage — every story maps to concrete hunks/files (above); no capability present that no story asks for.
- [PASS] D6 No secrets / stray deps — diff scan for `sk-*`, `AIza`, private keys, inline api keys → none; `OPENROUTER_API_KEY` only read from env, in-memory AuthStorage, nothing written. Deps only `@earendil-works/pi-coding-agent` + `ws`, both PRD-mandated.
- [PASS] D7 Implementer report ↔ diff — revision report claims match the diff: US5 fix (`append_artefact` mkdir) present, guarding test present, `21 passed` reproduced, SMOKE PASS reproduced, fetch_url PASS reproduced, node --check OK, rebuild-index + `/search` reproduced. Only "real OpenRouter" not reproducible (recorded deferred). Nothing silently dropped.

## Judgment checks

- [PASS] J1 Story intent — observable behavior each story implies works from the diff and run verification (US5 now included). Multi-turn context, fetch-on-url, evidence envelope, relevance search all behave as described under mock/fixture.
- [PASS] J2 PRD-decision conformance — Decisions 01–06 honored: pi SDK WS service on :8766; OpenRouter server-side key only; exactly one `fetch_url` tool; artefact + `sessions/<uuid>/session.jsonl` evidence model; plain-files + FTS5 BM25 KB; browser control deferred. Recorded, non-blocking deviations unchanged: `fetch_url.js` (not `.ts`), `deepseek/deepseek-v4-flash` alias + temperature intent (~0.2 not force-injected — pi controls inference temp; documented in `models.mjs`), in-memory auth/no `models.json`, `/search` auto-rebuild-on-missing-index (a harmless convenience beyond the strict "manual/cron" wording — index is derived).
- [PASS] J3 Edge/error paths — fetch caps/timeouts/protocol handled; invalid-FTS query → 400; agent-unavailable/reconnect states; and now the missing-`data/` first-save path is handled (the prior J3 blocker). No new blocking edge defect found.
- [PASS] J4 Ponytail review — see Advisory findings + Ponytail debt below (ponytail skills not mounted in this container; pass applied manually per the documented tag/format methodology). No over-engineering is blocking; complexity is largely justified by the PRD's search/agent requirements.
- [PASS] J5 UAT gaps — precise list below.

## Findings

### Blocking (→ REQUEST_CHANGES)
- None. The prior blocking finding (`capture/server/server.py` `append_artefact` not creating the parent `data/` dir → 500 on fresh-checkout plain save, breaking US5) is **resolved** and verified by a new regression test and a live 200 POST.

### Advisory (consider / over-engineering)
- `capture/extension/sidepanel.js` (~`updateAgentControls`) — `agentAskBtn.disabled = agentBusy || !!(current && current.tweet_url) === false;` has inverted/ambiguous precedence (works, but reads wrong). `native` — write the positive form: `agentBusy || !(current && current.tweet_url)`.
- `capture/server/index.py` `build_fts_query` (~70 lines) — hand-rolled FTS5 MATCH translator for AND/OR/phrases/`author:` qualifiers/prefix; justified by the PRD's search criteria but the most complex new member. `shrink` — acceptable as-is.
- `capture/server/index.py` (`search`) — `total = len(rows)` computed after `LIMIT`, so `/search.total` reflects the capped page, not the true match count. `native` — `COUNT(*)` before the LIMIT if consumers rely on total. Advisory (default limit 50; low impact for personal use).
- `capture/agent-service/server.js` (`disposeForSocket`) + `sidepanel.js` (`askAgent` sends `messages:[]`) — an in-memory session is dropped on socket close and the panel does not pass its `agentMessages` transcript on a reconnect `ask`, so a follow-up after a mid-capture service restart/reconnect loses capture context (new session, fresh tree injection). Edge case; `shrink`/document — acceptable for the v1 single-session UAT flow, worth wiring `messages` through on reconnect in a later phase.

## Ponytail debt (harvested from changed files)
- No `ponytail:` shortcut markers found in changed files (`grep -rn ponytail capture/` → none). No pre-existing debt markers to carry forward.

## UAT hand-off list
1. **US5 (re-validate the fix on real hardware):** on a machine where `capture/server/data/` does NOT exist yet and the agent service is stopped, Save a capture — it must succeed as "today" (the fix produced a 200 for exactly this in-sandbox).
2. `cd capture/agent-service && npm install`, run `OPENROUTER_API_KEY=… node server.js` (→ ws://127.0.0.1:8766); confirm a real ask streams, uses `fetch_url` on a linked url, and `settled` returns model + cost.
3. Load the unpacked extension on x.com; capture a tweet with comments + links; Ask → stream → follow-up → "⚙ fetched <url>" tool feedback; confirm the Ask control enables only when a tweet_url is present.
4. Save with the agent running: confirm the `data/artefacts.jsonl` line carries the `agent` envelope and `data/sessions/<uuid>/session.jsonl` exists and opens (pi-native v3, valid for `extract-context`).
5. Search: `bin/rebuild-index.py` then `curl "http://127.0.0.1:8765/search?q=<term>"` (content / author / url), confirm relevance ordering + returned `agent.sessionFile` opens the evidence.
6. Upgrade check: move any existing `capture/server/artefacts.jsonl` → `capture/server/data/artefacts.jsonl` once (no re-capture); confirm `CAPTURE_DATA` still overrides.
7. Approve the documented deviations (unchanged, per implementer decision 01): `fetch_url.js` (not `.ts`), `deepseek/deepseek-v4-flash` alias + temperature-intent (pi controls inference temp), in-memory auth (no `auth.json`/`models.json` written), `/search` auto-rebuild-on-missing-index.
