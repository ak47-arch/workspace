# PRD Review (Round 2 — Re-review)

- Reviewed: docs/prd-queue/2026-08-08-extension-inline-agent.md (slug: extension-inline-agent, category: Large)

## Deterministic checks

- [PASS] Header fields — **Date** 2026-08-08 21:50, **Status** Review, **Owner** feed_analyser / capture instrument, **Task** extension-inline-agent, **Session** and all six **Decisions** present and correctly formatted.
- [PASS] Required body sections (Large) — Problem statement, Solution overview, 7 numbered user stories, Implementation decisions, Testing decisions, Out-of-scope; `## Architecture` with system diagram, data-flow steps, endpoint contracts, and data model changes; `## Program Design` with file-tree diff, call-stack trees, and key types/signatures. All present.
- [PASS] Location / file-map — Program Design file-tree diff names every file that changes (extension sidepanel.js/sidepanel.html/agent-client.js, new agent-service/, server.py/index.py/bin/rebuild-index.py, data/ layout) and matches the on-disk plain-JS structure. New-single-value items (NodeTree, AgentEnvelope, CaptureIndex) are declared with signatures.
- [PASS] Acceptance — Testing decisions enumerates seams (agent-service WS integration, fetch_url unit, server read API + index integration, manual side-panel, regression) with concrete runnable commands, plus "Done = UAT: end-to-end capture with multi-turn ask, save, search, and opening linked session evidence."
- [PASS] Context pointers — Header links session trace and six decision records; Further notes adds the openwiki-staleness caveat so the context chain resolves to code + PRD.
- [PASS] User stories numbered and independently checkable — US1-US7 each map to an observable behavior and a testing seam (US2 anchored by a `fetch_url` example; US6 by bm25 ordering).
- [PASS] Task-file consistency — docs/tasks/extension-inline-agent.md slug matches, category Large matches, docs/tasks.txt:80 carries `[extension-inline-agent]`, slug unique (grep count = 1).
- [PASS] Linked session + decision files exist — session.jsonl (113 lines, real planning trace incl. product-layer run + OpenRouter model id) and decisions/01..06 all present.

## Non-deterministic checks

- [PASS] Self-containedness as entry point — With the PRD + factory-context + actual code, an implementation agent can route end-to-end: where each change lands (file-tree diff), the WS protocol, the envelope + /search contracts, the type shapes, the storage relocation, and how to verify (seams + concrete commands + UAT). Remaining discovery (exact pi SDK serialize call, SQLite tokenizer detail) is correctly left as "how".
- [PASS] Checkability — Every user story has an observable outcome and at least one seam; the Done criterion is a concrete end-to-end UAT; the F1 regression (two-store divergence) is now closed by an explicit single-store rule.
- [PASS] Decision resolution — Decisions 01-06 resolve the hard questions (where the agent runs, key placement, tool surface, artefact/evidence model, KB store, browser-control deferral). Round-1 open items (model id, caps values) now have concrete values.
- [PASS] Boundaries — Out-of-scope list (browser control, general web search, answer editing, vector search, auto-capture/engagement/media, image understanding) plus US7 as a regression guard on the existing flow. Explicit "do not touch" scope holds.
- [PASS] Authority split — PRD carries the what/where/acceptance (scope, contracts, types, file map, relocation). The how (pi SDK internals, SQLite pragmas, WS framing) is left to agent discovery without over-prescribing.

## Findings

### Blocking (must fix before implementation-ready)

- None. F1 (round 1) is fully resolved by the new "Storage relocation (explicit)" subsection and updated file-tree diff; the remaining items were advisory and addressed.

### Advisory (consider)

- A-envelope model string: Implementation decisions pins default `deepseek/deepseek-v4-flash-0731` (PRD line 84, matching session.jsonl:2), but the endpoint-contract `settled` example and the data-model envelope example both still show `"model": "deepseek/deepseek-v4-flash"`. Non-blocking (the field is a metadata string and the pinned default is authoritative), but aligning the two examples would remove a cosmetic mismatch for the implementer.
- A-gitignore note: the `.gitignore` rule referencing `capture/server/artefacts.jsonl` lives in the repo-root `.gitignore` (line 35), not a capture-level one. The PRD correctly says "the rule moves with the file" and lists the new `capture/server/data/*` rules; no action needed, just confirming the rule location for the implementer.
- tasks.txt:80 still shows `(queued)` while the task file is `prd-ready`, consistent with the dashboard's observed completion-only promotion; lifecycle trace remains legible.

## Verdict

READY — all round-1 blocking (F1 storage relocation) and advisory (A1-A6) findings are addressed and verified against the actual code; the PRD is now a routeable, self-contained entry point for autonomous implementation with no open questions that would force user interaction.
