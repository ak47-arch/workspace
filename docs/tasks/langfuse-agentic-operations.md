# Task: langfuse-agentic-operations

**Status**: in-prd
**Category**: Large
**Project**: langfuse
**Created**: 2026-08-03 01:40
**Source**: docs/tasks.txt — `integrate official langfuse skill (langfuse)`, `set up langfuse use and operation agentically (langfuse)`, and `integrate langfuse with all applications (all)`

## Artifacts

- Plan: `docs/prd-queue/2026-08-09-langfuse-agentic-operations.md`
- Teaching workspace: `docs/teach/langfuse/`

## Progress

- [x] Integrate official Langfuse skill as internal component referenced by thin wrapper — wrapper `.agents/skills/langfuse-tracing/SKILL.md` now has an **Official skill** section pointing to `opensource/langfuse-skills/skills/langfuse/` (SKILL.md + 11 references); repo current at upstream `b9958d6` (2026-08-07), updated via `git pull --ff-only`
- [x] Verify official skill path resolves — `opensource/langfuse-skills/skills/langfuse/SKILL.md` exists (8,134 bytes, 2026-07-31)
- [x] Self-hosted Langfuse upgraded v3 → v4.6.0 — migrations 0001–0046 applied, data restored (4,293 observations, 339 traces), pi tracing verified live in dual write mode (decision record: `docs/knowledge/sessions/019fc40a-…/decisions/01-langfuse-v3-to-v4-upgrade.md`)
- [x] Agentic operations (Level B: start/stop/restart/health/logs) — Operations section in wrapper SKILL.md (verified against live stack)
- [x] Integrate Langfuse into all first-party applications (survey + phased plan in task file: `llm/` first, then `survival-infrastructure/`, phase 2 apps; execution gated on project preflights)
- [x] PRD → `docs/prd-queue/2026-08-09-langfuse-agentic-operations.md`

## First-party integration inventory (survey 2026-08-09)

| Project | What it is | LLM/agent surface | Langfuse today | Priority |
|---|---|---|---|---|
| `pi` (this agent + `.pi/extensions/langfuse-tracing.ts`) | Coding agent harness | Every agent turn (LLM + tools) | ✅ **Integrated** (extension, verified live on v4) | — done |
| `llm/` | Inference server + client (`llm_client`, `monitoring.py`) | All model requests through one client | ❌ none | **High** — single integration point covers all consumers |
| `survival-infrastructure/` | Staged data pipeline: collection → extraction → analysis → downstream | Extraction/enrichment/analysis stages (LLM-heavy: 1229 file hits) | ❌ none | **High** — quality of extraction is the product risk |
| `headroom-pi/` | Compression proxy for pi | Passes/compresses agent traffic (3 hits) | ❌ none | **Medium** — proxy-level spans if instrumented |
| `feed_analyser/capture/` | Chrome extension + local server (X post capture) | Inline agent reasoning over captures (212 hits) | ❌ none | Medium — agent conversations are valuable eval data |
| `workspace-portability/` | Backup/restore/bootstrap scripts | Minimal (6 hits, script-level) | ❌ none | Low — only if it spawns LLM steps |
| `resume/` | Resume editor (deferred) | None (0 hits) | ❌ none | Skip (deferred) |

**Integration plan (phased, cheapest-first):**
1. `llm/` client — wrap `llm_client` request path with the Langfuse SDK (single choke point; all consumers inherit tracing) — pending `llm/` preflight.
2. `survival-infrastructure/` — trace extraction/enrichment steps with OpenTelemetry or Langfuse SDK spans.
3. `headroom-pi/` + `feed_analyser/capture/` — treat as phase 2; agent-native, use pi-extension pattern.
4. `resume/` — skip while deferred.

**Precondition**: `llm/` and `survival-infrastructure/` preflight currently 🟡 (broken per `docs/factory-context.md`); integration work must wait for those stacks to run or proceed against their API contracts only.

## Sessions

- _(this session)_

## Decisions

- [01-langfuse-v3-to-v4-upgrade](../knowledge/sessions/019fc40a-5458-7310-89c4-53e098060973/decisions/01-langfuse-v3-to-v4-upgrade.md)