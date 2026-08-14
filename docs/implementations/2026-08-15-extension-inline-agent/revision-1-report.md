# Implementation REVISION Report — extension-inline-agent

**Task**: extension-inline-agent
**Session**: 60c0c537-b9c7-4c4c-8b8a-0be438950151 (reused from the original run)
**Date**: 2026-08-14
**PRD**: `docs/prd-queue/2026-08-08-extension-inline-agent.md`
**Binding authority**: `/sandbox/review/report.md` + `/sandbox/review/decisions/01-extension-inline-agent.md`
**Worktree**: `/sandbox/worktree` (same branch `factory/extension-inline-agent/…`; no git commands run here — host owns git)

## What this revision fixed

The review found **one blocking** issue (VERDICT REQUEST_CHANGES) and **no other
blocking defects**. Per the binding scope rule ("fix EXACTLY what the findings
scope — no more, no less"), this revision applies **only the blocking fix**. The
review's advisory items were explicitly marked non-blocking / acceptable-as-is
and are intentionally left untouched.

### Blocking fix (review decision #1)
- **File**: `capture/server/server.py` (`append_artefact`)
- **Problem**: `target.open("a")` never created the parent `data/` dir. On a
  fresh checkout `data/` is gitignored/untracked, `run-server.sh` and server
  startup create nothing, and only `index.py.rebuild()` (on `/search`) or the
  agent-service `persistSession` (on an ask) mkdir it. So the first **plain Save
  with the agent unavailable** — exactly US5's "saving still works as today" —
  raised an unhandled `FileNotFoundError` → HTTP 500.
- **Fix**: `target.parent.mkdir(parents=True, exist_ok=True)` as the first line
  of `append_artefact` (mirrors `index.py.rebuild`, which already did this).
- **Guarding test added**: `tests/test_capture.py` →
  `test_save_creates_missing_data_dir` asserts a plain save to a non-existent
  parent dir returns 200, creates the parent, and persists the artefact.

## Story status (after fix)

| Story | Status | Evidence |
|---|---|---|
| US1 ask → streamed answer | DONE (unchanged) | `sidepanel.html/js`, `agent-client.js`, `agent-service/server.js`; mock smoke PASS; real-run claim recorded |
| US2 fetch/read capture urls | DONE (unchanged) | `tools/fetch_url.js`; `fetch_url.test.mjs` PASS |
| US3 follow-ups keep context | DONE (unchanged) | per-`captureId` in-memory session; mock smoke ask→settled→follow_up→settled |
| US4 save tree + evidence envelope | DONE (unchanged) | `persist.js` pi-native v3 session.jsonl; envelope validation/persistence; smoke verifies evidence file |
| **US5 agent unavailable → save still works** | **DONE (fixed)** | `server.py` now creates `data/`; live POST with a non-existent data dir → **200** + file written; regression test added |
| US6 search, relevance-ranked, links evidence | DONE (unchanged) | `index.py` FTS5 BM25, `/search`, rebuild-index; search tests PASS |
| US7 existing capture flow unchanged | DONE (unchanged) | original 10-test regression PASS; `content.js`/`background.js` untouched |

## Verification results

| Check | Command | Result |
|---|---|---|
| Python suite (regression + seams + new US5 test) | `cd capture/server && .venv/bin/python -m pytest tests/ -q` | **21 passed** (10 original + 4 envelope + 6 search + **1 new US5 regression**) |
| **US5 live runtime check** (fresh, non-existent data dir, plain save, agent service down) | start uvicorn with `CAPTURE_DATA=/tmp/…/nonexistent/deep/data/artefacts.jsonl`, then `POST /api/capture` | **HTTP 200** `{"status":"saved",…}`; `data/` dir + file created — the exact scenario the review reproduced as a 500 |
| Agent service smoke (mock, no key) | `AGENT_MOCK=1 node server.js` + `node test/smoke.mjs <ws-url>` | unchanged from original run — SMOKE PASS (reported in original review, reproducible) |
| fetch_url caps | `node test/fetch_url.test.mjs` | PASS (unchanged from original run) |
| rebuild-index + `/search` | `bin/rebuild-index.py` + `/search` | PASS (unchanged from original run / review) |
| Extension JS syntax | `node --check` | PASS (unchanged) |
| Real OpenRouter inference + full browser e2e | — | DEFERRED to UAT (needs your key + live browser panel) |

## UAT hand-off list (unchanged from original, plus the US5 item the review flagged)

1. **US5 (the blocking fix — re-validate):** on a machine where
   `capture/server/data/` does NOT exist yet and the agent service is stopped,
   Save a capture — it must succeed as "today" (this is what the fix produced a
   200 for).
2. `cd capture/agent-service && npm install`, run `OPENROUTER_API_KEY=… node
   server.js` (→ ws://127.0.0.1:8766); confirm a real ask streams, uses
   `fetch_url` on a linked url, and settle returns model+cost.
3. Load the unpacked extension on x.com; capture a tweet with comments + links;
   Ask → stream → follow-up → "fetched <url>" feedback.
4. Save with the agent running: confirm `data/artefacts.jsonl` line carries the
   `agent` envelope and `data/sessions/<uuid>/session.jsonl` exists and opens.
5. Search: `bin/rebuild-index.py` then `curl "http://127.0.0.1:8765/search?q=…"`
   (content / author / url), confirm relevance ordering + `agent.sessionFile`.
6. Upgrade check: move any existing `capture/server/artefacts.jsonl` →
   `capture/server/data/artefacts.jsonl` once (no re-capture); `CAPTURE_DATA`
   still overrides.
7. Approve documented deviations (unchanged, per implementer decision 01):
   `fetch_url.js` (not `.ts`), `deepseek/deepseek-v4-flash` alias + temperature
   intent, in-memory auth, `/search` auto-rebuild-on-missing-index.

## Decisions

- No new design decisions emerged from this revision (it applied the review's
  single binding fix verbatim). Decision record `outbox/decisions/01-extension-inline-agent.md`
  from the original run stands; the review's blocking decision is acknowledged
  and satisfied here.
