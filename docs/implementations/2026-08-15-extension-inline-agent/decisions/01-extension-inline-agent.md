## Decision: Implementation deviations & small decisions for extension-inline-agent

**Status**: accepted
**Date**: 2026-08-11 (original run); revision 2026-08-14 — unchanged
**Task**: extension-inline-agent
**Project**: feed_analyser / capture
**Session**: 60c0c537-b9c7-4c4c-8b8a-0be438950151

This record captures the small decisions that emerged while implementing the PRD
inside the sandbox. The PRD decisions 01–06 (pi SDK service, OpenRouter server
key, fetch_url-only tools, artefact-session evidence, plain-files+FTS5, defer
browser control) were all followed as written. The review of the PR approved
these deviations; the revision added only the review's blocking `data/` mkdir
fix (no change to any of these decisions).

### Context / Problem

The PRD's file-tree lists `tools/fetch_url.ts` (TypeScript) and says the model
default is the dated id `deepseek/deepseek-v4-flash-0731` with "thinking on,
temperature ~0.2". It also implies the agent service may write credential /
registry files. The concrete pi SDK available in-sandbox differs in small ways
from the PRD's phrasing, which required pragmatic, deterministic choices.

### Alternatives considered

All deviations below are the minimal choices that keep the documented acceptance
commands runnable verbatim (`node server.js`, `pytest`, `rebuild-index.py`
+ `curl /search`).

### Decision & Rationale

1. **`tools/fetch_url.js` (plain ESM) rather than `fetch_url.ts`.** The service
   is deliberately build-free — it must run with `node server.js` with no TS
   compile step, and `package.json` is already `"type":"module"`. Behaviour is
   identical (uses `defineTool` + typebox). Rationale: smallest change that
   satisfies the acceptance; avoids a build pipeline for one file.

2. **Default model alias `deepseek/deepseek-v4-flash` (not the `-0731` dated id)
   and temperature not force-injected.** `deepseek/deepseek-v4-flash` is the
   built-in alias pi resolves for OpenRouter (with reasoning + pricing); the
   dated id is an implementation detail of the planning session. pi's SDK does
   not expose a per-session `temperature` knob to callers for reasoning models
   (it lives on provider `StreamOptions` pi controls internally), so the PRD's
   "~0.2" is honoured as documented intent. Both are overridable via
   `AGENT_MODEL` and, for pricing, a `models.json` — noted for UAT.

3. **In-memory `AuthStorage` + `ModelRegistry` in the agent service (no
   credential/registry files on disk).** The PRD says the key lives in the
   service env; using in-memory auth with `setRuntimeApiKey("openrouter",
   OPENROUTER_API_KEY)` satisfies that while keeping the repo free of stray
   `auth.json`/`models.json` files and never writing a key to disk.

4. **`GET /search` auto-rebuilds the derived index on first use if missing.**
   The index is derived + rebuildable by design (Decision 05); auto-building on
   a read of a missing `index.db` is a harmless convenience so `/search` works
   immediately after `run-server.sh`, while `bin/rebuild-index.py` remains the
   explicit manual/cron path. (Reviewer noted this is beyond the strict PRD
   "manual/cron" wording but harmless — advisory, kept.)

5. **`fetch_url` uses the runtime's global `fetch` (native redirect handling)
   with size/timeout caps**, rather than `undici.request(maxRedirections)` —
   undici v7 moved redirect handling to an interceptor. Caps are unchanged
   (~1 MB body / 30 s).

### Revision (2026-08-14)

The review's single **blocking** finding — `append_artefact` did not create the
`data/` parent dir, so a plain Save on a fresh checkout raised `FileNotFoundError`
→ HTTP 500 (US5) — was fixed verbatim in `capture/server/server.py` with
`target.parent.mkdir(parents=True, exist_ok=True)` and guarded by a new
`test_save_creates_missing_data_dir` regression test (suite now 21 passed). The
review's advisory notes (sidepanel disable-expression precedence, `/search`
`total` reflecting the post-LIMIT page, socket-close session-drop with empty
reconnect `messages`) were marked non-blocking/acceptable by the review and are
intentionally not changed to avoid scope expansion.

### Consequences

- The agent-service is easier to run and audit (no build step, no stray files);
  the only operational prerequisite is `npm install` + `OPENROUTER_API_KEY`.
- Saving works on a fresh checkout with or without the agent (US5 guaranteed).
- Anyone wanting the dated model id or a specific temperature/pricing path can
  adjust `AGENT_MODEL` / provide `models.json` without code changes.

### Revision triggers

- If the user wants the dated `-0731` model id pinned, or a specific
  temperature, wire `AGENT_MODEL` + a custom `models.json`.
- If the repo should be byte-conformant to the PRD file-tree (`.ts` source),
  add a TS build step and keep unit tests in TS.
