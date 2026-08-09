# PRD Review (Round 3 — Confirmation pass)

- Reviewed: docs/prd-queue/2026-08-08-extension-inline-agent.md (slug: extension-inline-agent, category: Large, project: feed_analyser)

## Deterministic checks

- [PASS] Header fields — **Date** 2026-08-08 21:50, **Status** Final (line 4; changed Review → Final since round 2, per the accepted factory rule), **Owner** feed_analyser / capture instrument, **Task** extension-inline-agent, **Session** and all six **Decisions** present and correctly formatted.
- [PASS] Required body sections (Large) — Problem statement, Solution overview, 7 numbered user stories, Implementation decisions, Testing decisions, Out-of-scope; `## Architecture` with system diagram, stepwise data flow, endpoint contracts, and data model changes; `## Program Design` with file-tree diff, call-stack trees, and key types/signatures. All present.
- [PASS] Location / file-map — Program Design file-tree diff names every file that changes and the new data/ layout, including the now-specified `artefacts.jsonl` relocation (`server/artefacts.jsonl` → `server/data/artefacts.jsonl` with carry-over and `DEFAULT_DATA_PATH`/`CAPTURE_DATA` handling).
- [PASS] Acceptance — Testing decisions enumerates five seams with concrete commands (`cd feed_analyser/capture/server && .venv/bin/python -m pytest tests/`, `node server.js` smoke check, `bin/rebuild-index.py` + `curl /search`), plus "Done = UAT: an end-to-end capture with a multi-turn ask, save, search, and opening the linked session evidence all work on the user's machine."
- [PASS] Context pointers — Header links the session trace and six decision records; Further notes adds the openwiki-staleness caveat (capture extension/server pages describe legacy architecture) so the context chain resolves to code + PRD.
- [PASS] User stories numbered and independently checkable — US1–US7 each map to an observable behavior and a testing seam (US2 anchored by a `fetch_url` example; US6 by bm25 ordering; US7 regression-guards the existing capture flow).
- [PASS] Task-file consistency — docs/tasks/extension-inline-agent.md slug matches, category Large, project feed_analyser, status prd-ready; docs/tasks.txt:80 carries `[extension-inline-agent]`, slug unique (grep count = 1).
- [PASS] Linked session + decision files exist — session.jsonl (planning trace incl. `model_change` `deepseek/deepseek-v4-flash-0731` at line 2) and decisions/01–06 present on disk.

## Non-deterministic checks

- [PASS] Self-containedness as entry point — Unchanged since round 2: with the PRD + factory-context + actual code an implementation agent knows what to build, where (per-file diff), which contracts to honor (WS protocol, envelope, /search, NodeTree/AgentEnvelope shapes), and how to verify (seams + commands + UAT). Pinned default model id (`deepseek-v4-flash-0731`) and sized fetch_url caps (≈1 MB / 30 s) remove the round-1 discovery guesses.
- [PASS] Checkability — Every user story has an observable outcome and at least one seam; the Done criterion is a concrete end-to-end UAT; the single-store regression (round-1 F1) stays closed by the explicit storage-relocation subsection.
- [PASS] Decision resolution — Decisions 01–06 resolve the hard questions (agent host, key placement, tool surface, artefact/evidence model, KB store, browser-control deferral). The two round-2 advisories re-verified below remain cosmetic, not decision-gaps.
- [PASS] Boundaries — Out-of-scope list (browser control, general web search, answer editing/regen, vector search, auto-capture/engagement/media, image understanding) plus US7 as the regression guard; no growth of scope between rounds.
- [PASS] Authority split — PRD carries the what/where/acceptance (scope, contracts, types, file map, relocation); the how (exact pi SDK serialize calls, SQLite pragmas, WS framing) is left to agent discovery without over-prescription.

## Findings

### Blocking (must fix before implementation-ready)

- None. No content changed since the round-2 READY verdict (verified below); the round-2 advisories re-confirmed as non-blocking.

### Advisory (consider)

- A1 (round-2 re-check, stays advisory) — Model-string examples vs pinned default: Implementation decisions (line 84) pins `deepseek/deepseek-v4-flash-0731` — the id recorded verbatim in session.jsonl:2 (`modelId: "deepseek/deepseek-v4-flash-0731"`) — but the `settled` contract example (line 217) and the envelope data-model example (line 241) still show `"model": "deepseek/deepseek-v4-flash"` (lines 167/286 use the bare `deepseek-v4-flash` as descriptive shorthand, which is fine). Not a blocking call: the field is a *reported* metadata string in both examples ("which model was used"), while the pinned default is the *config* value the agent must adopt; no implementation decision depends on the example strings.
- A2 (round-2 re-check, confirmed+corrected) — .gitignore rule location: the workspace-root `.gitignore` is not where the rule lives — it excludes the whole `/feed_analyser/` directory (repo-root .gitignore line 1), and `feed_analyser/` is its own git repo. The actual rule is `capture/server/artefacts.jsonl` at `feed_analyser/.gitignore:35` (under the "# Capture data" comment, line 34). Round-2's "repo-root, line 35" was imprecise wording; the PRD itself is consistent — the storage-relocation section says "The `.gitignore` rule moves with the file" and lists the new rules in the same project-relative style (`capture/server/data/artefacts.jsonl`, `capture/server/data/sessions/`, `capture/server/data/index.db`), so the implementer will find and move the rule at feed_analyser/.gitignore:35 without ambiguity. No PRD change needed; consider correcting the wording in the review record only.
- A3 (unchanged from round 2) — docs/tasks.txt:80 still shows `(queued)` while the task file is `prd-ready`, consistent with the dashboard's observed completion-only promotion convention; lifecycle trace stays legible.

## Change verification (round 2 → round 3)

- `git log -- docs/prd-queue/2026-08-08-extension-inline-agent.md` shows no commits after `b689ea9` ("docs(prd): mark reviewed/completed PRDs Final"); that commit's PRD diff is the status flip (`**Status**: Review` → `**Status**: Final`) plus the F1/A1–A6 revisions that round-2 was already written against. `git status` is clean. Confirmed: header-only change since round 2, exactly as stated.

## Verdict

READY — round-2 READY holds: only the header status flipped Review → Final (factory rule), no content changed, all deterministic + judgment checks pass, and both round-2 advisories are re-confirmed cosmetic (model-string examples vs the pinned `deepseek-v4-flash-0731` default; .gitignore rule correctly located at feed_analyser/.gitignore:35 with the PRD's project-relative rules matching) — nothing remains that would force user interaction.
