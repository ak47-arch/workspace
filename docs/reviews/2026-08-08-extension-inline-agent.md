# PRD Review

- Reviewed: docs/prd-queue/2026-08-08-extension-inline-agent.md (slug: extension-inline-agent, category: Large)

## Deterministic checks

- [PASS] Header fields — Date 2026-08-08 21:50, Status Review, Owner feed_analyser / capture instrument, Task extension-inline-agent, Session and Decisions (all six) present and correctly formatted.
- [PASS] Required body sections (Large) — Problem statement, Solution overview, 7 numbered user stories, Implementation decisions, Testing decisions, Out-of-scope; Architecture with system diagram, data flow, endpoint contracts, and data model changes; Program Design with file-tree diff, call-stack trees, and key types/signatures. All present.
- [PASS] Location / file-map — Program Design file-tree diff names every file that changes and matches the actual on-disk layout (plain-JS sidepanel.js, manifest.json, server.py with /api/capture, artefacts.jsonl beside it). Caveat: one relocation inside that map is under-specified (see Blocking F1).
- [PASS] Acceptance — Testing decisions enumerates seams (agent-service integration, fetch_url unit, server read API/index integration, manual side-panel) plus "Done = UAT: an end-to-end capture with a multi-turn ask, save, search, and opening the linked session evidence all work on the user's machine." Concrete verification commands omitted (pytest mentioned by name only) — advisory.
- [PASS] Context pointers — Header links the session trace and all six decision records (docs/knowledge/sessions/019fd8a4-73ca-7c92-bbcc-b5d74e7d0817/session.jsonl + decisions/01..06). Vision/openwiki not linked inline but reachable via docs/factory-context.md; note openwiki capture pages are stale (advisory).
- [PASS] User stories numbered and independently checkable — US1-US7 each map to a distinct observable behavior and a testing seam. US2 ("when it is relevant") is softened by a concrete example; US6 "relevance-ranked" is pinned by bm25 ordering.
- [PASS] Task-file consistency — docs/tasks/extension-inline-agent.md slug matches; category Large matches; docs/tasks.txt:80 carries [extension-inline-agent] and the slug is unique (grep count = 1). Minor: tasks.txt shows (queued) while the task file is prd-ready — consistent with the observed dashboard convention; advisory only.
- [PASS] Linked session + decision files exist — session.jsonl (113 lines, real planning trace incl. product-layer run) and decisions/01..06 all present on disk.

## Non-deterministic checks

- [PASS] Self-containedness as entry point — With the PRD + factory-context.md + the actual code, an implementation agent knows what to build, where (per-file diff), which interfaces to honor (WS protocol, envelope, /search contract, NodeTree shape), and how to verify (seams + UAT). Two discovery items remain reasonable for the agent: the exact OpenRouter model id string and the pi SDK serialization API for persisting session.jsonl (mechanism correctly left as "how").
- [PASS] Checkability — The strongest part of the PRD: every story has an observable outcome and at least one test seam; the Done criterion is a concrete end-to-end UAT scenario.
- [PASS] Decision resolution — Decisions 01-06 close every major ambiguity that would otherwise force user interaction: where the agent runs (SDK service vs embedded vs RPC), key placement (server-side), tool surface (fetch_url only), artefact/evidence model (envelope + pi-native session.jsonl), KB store (plain files + FTS5 + read API), and the browser-control deferral. Remaining open items (cap values, model id, tokenizer choice) are implementation-detail level.
- [PASS] Boundaries — Explicit out-of-scope list (browser control, general web search, answer editing, vector search, auto-capture/engagement/media, image understanding) plus US7 as a regression guard on the existing capture flow. Could additionally state "do not touch llm/ or other factory modules" — advisory.
- [PASS] Authority split — PRD carries the what/where/acceptance (scope, contracts, types, file map); the how (exact pi SDK calls, SQLite pragmas, WS framing details) is left to the agent's discovery. Interfaces are specified at contract level without over-prescribing internals.

## Findings

### Blocking (must fix before implementation-ready)

- F1 — docs/prd-queue/2026-08-08-extension-inline-agent.md (Program Design file-tree diff + Further notes): artefacts storage relocation is under-specified. The PRD states the target layout is capture/server/data/ containing artefacts.jsonl, sessions/, index.db — but the file exists today at capture/server/artefacts.jsonl (server.py DEFAULT_DATA_PATH, run-server.sh default, feed_analyser/.gitignore rule capture/server/artefacts.jsonl). The diff lists only "+ GET /search" and envelope validation for server.py — no change to DEFAULT_DATA_PATH, no mention of moving the existing file, and no .gitignore handling for the relocated artefacts rule. A literal implementation appends captures to the old path while bin/rebuild-index.py reads data/artefacts.jsonl, producing two divergent stores: /search misses freshly saved captures and US6 + the UAT "search after save" silently fail. Fix is one clarifying line: state that artefacts.jsonl moves into data/, that the existing file is carried over, that DEFAULT_DATA_PATH / run-server.sh defaults change to match, and that the gitignore rule follows the file.

### Advisory (consider)

- A1 — Exact OpenRouter model id: PRD uses deepseek/deepseek-v4-flash; the planning session's own model_change line records deepseek/deepseek-v4-flash-0731. The implementer will need to confirm the resolvable id against OpenRouter; worth pinning in the PRD or explicitly delegating to discovery.
- A2 — feed_analyser/openwiki/capture/{extension.md, server.md} are stale: they document the archived legacy architecture (React popup src/, SQLite captures.db, config.yaml, /api/v1/capture), which contradicts the current plain-JS extension and JSONL FastAPI server. Following the context chain into openwiki would mislead an autonomous implementer; code + PRD are the truth. Recommend a one-line note in the PRD ("openwiki capture pages describe the archived legacy version") and an OpenWiki refresh as follow-up.
- A3 — fetch_url caps are named but never sized (bytes, timeout). The Testing decisions unit-test "caps, timeouts" implies values must exist; a default in the PRD (e.g. 1 MB / 30 s) would remove a guess, though this is agent-settable.
- A4 — Acceptance lists test seams but no concrete commands (e.g. pytest capture/server/tests, a node server.js smoke check, python server/bin/rebuild-index.py). Fine for a human UAT, but concrete runnable commands would tighten "done" for an autonomous agent.
- A5 — docs/tasks.txt:80 label (queued) vs task-file status prd-ready. Consistent with the dashboard's observed complete-only promotion convention, but worth noting so the lifecycle trace stays legible.
- A6 — Envelope validation spec is thin ("validate optional agent envelope"). The envelope-parse-and-link test in Testing decisions anchors it, but stating the exact rule (e.g. agent present implies sessionId + sessionFile required; server need not check session-file existence at save time) would remove ambiguity.

## Verdict

NOT READY — the PRD is otherwise excellent (complete Large-category structure, checkable stories, decisions 01-06 resolve the hard questions, contracts and file map match reality), but Blocking F1 (artefacts.jsonl relocation into capture/server/data/ is under-specified and admits a silently divergent two-store implementation) must be clarified before an implementation agent can route on it; a one-line fix unblocks.
