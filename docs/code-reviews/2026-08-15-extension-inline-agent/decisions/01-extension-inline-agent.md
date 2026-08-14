# Code Review — extension-inline-agent (session f8cb56ec-d6f6-4641-bf7f-126c039c3879)

**Decision**: REQUEST_CHANGES due to one blocking robustness/correctness gap in the save path. All 7 stories otherwise implemented, all PRD verification commands that can run in-sandbox pass, no secrets, scope contained.

**Status**: accepted (reviewer gate)
**Date**: 2026-08-14
**Task**: extension-inline-agent
**Project**: feed_analyser / capture instrument

## Context

Reviewing PR ak47-arch/feed_analyser#1 against PRD
`docs/prd-queue/2026-08-08-extension-inline-agent.md` (base 1771fdc → head 24e60a8).
Verified: 20 pytest pass, agent-service mock smoke PASS, fetch_url caps PASS,
rebuild-index + /search PASS, node --check PASS. Real OpenRouter run + full browser
e2e deferred to UAT (no key/live browser in sandbox).

## Decision / Rationale

1. **Blocking — `capture/server/server.py:60` `append_artefact` does not create the
   `data/` parent dir.** On a fresh checkout `data/` is gitignored/untracked,
   `run-server.sh` and server startup create nothing, and only `index.py.rebuild()`
   (on `/search`) or the agent-service `persistSession` (on an agent ask) mkdir it.
   Therefore the first **plain Save with the agent unavailable** — precisely US5's
   guarantee ("saving still works as today") — raises an unhandled `FileNotFoundError`
   → HTTP 500. Reproduced by a direct POST to `/api/capture` with a missing parent
   directory. **Recommended fix**: `target.parent.mkdir(parents=True, exist_ok=True)`
   at the top of `append_artefact` (mirrors `index.py:143`), or a startup mkdir of
   `data/`. Trivial but required before APPROVE.

2. **Advisory (non-blocking)**: `sidepanel.js:237` inverted/ambiguous disable
   expression; `index.py:230` `total` reflects the post-LIMIT page not true total;
   `server.js` drops in-memory session on socket close while the panel sends an empty
   `messages` on reconnect `ask` (follow-up context lost after a mid-capture
   restart); `/search` auto-rebuild-of-missing-index is a small documented deviation
   beyond the PRD "manual/cron" wording but harmless (index is derived).

3. **Accepted deviations (documented by implementer decision 01)**: `fetch_url.js`
   instead of `.ts` (build-free ESM), `deepseek/deepseek-v4-flash` alias instead of
   the dated `-0731` id + temperature not force-injected (pi controls inference temp
   for reasoning models), in-memory AuthStorage/ModelRegistry (no credential files
   on disk), global `fetch` for redirects. All overridable via `AGENT_MODEL` /
   `models.json`; surfaced in UAT.

## Consequences

- Fix the `data/` mkdir (one line) and re-review; the rest of the PR is ready.
- UAT must re-confirm Save-without-agent on a machine with no `data/` dir.
