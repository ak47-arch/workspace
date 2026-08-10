## Decision: Implementer runtime set — current model, langfuse-tracing, embedded ponytail, implementer-ops skill

**Status**: accepted
**Date**: 2026-08-10 20:59
**Task**: implementer-agent
**Project**: software-factory
**Session**: sessions/019fe7d2-aa31-77e6-8ea0-9df3d6b3c6ed/session.jsonl

### Context

The user required the implementer to run with its own special skills and extensions ("i want the implementer to have special skills and extensions that it runs with"), and pointed at `opensource/ponytail` ("skills for implementer agents", pulled to upstream `2ed6c52`). The factory already runs `langfuse-tracing` (pi extension captured per agent turn) and the review agent uses `deepseek/deepseek-v4-flash-0731`. Headless pi has `defaultProjectTrust` defaulting to "ask", which silently ignores project-local skills/extensions.

### Problem

Which runtime set does the implementer run with, and how is it made reliably active in a headless container (skills are normally load-on-demand, which an autonomous worker cannot be trusted to remember)?

### Alternatives

- **Load-on-demand skill** for ponytail — rejected: an autonomous implementer must be *forced* to stay lazy, not trusted to load the skill when relevant; unreliable.
- **Interactive `/ponytail` pi-extension** (lite/full/ultra modes, session persistence) — rejected for the headless worker: no UI/session to drive modes; the directive must be unconditional.
- **Embed ponytail in the implementer's system prompt as an always-on directive (chosen)**, with `opensource/ponytail` as the versioned source.

### Decision

- **Model**: `openrouter/deepseek/deepseek-v4-flash-0731` — the factory's current session model, per the user's instruction ("the current model will also be the implementer model"); per-run override via `IMPLEMENTER_MODEL` env (config, not rebuild).
- **Extensions**: `langfuse-tracing` only (discovered from the workspace root's `.pi/settings.json` with implementer `cwd=/workspace`); `herdr-agent-state`, `subagent`, and interactive guards excluded (leaf worker, no UI, monitoring deferred).
- **Skills**: `implementer-ops` (NEW — the factory run contract: brief, worktree, commit-early, verification protocol, report format, no-docs/no-secrets rules) + `implementer-save` (NEW — scoped decision capture taking the session dir explicitly); `save-knowledge`, `web-search`, `transcribe`, `product-layer`, and other factory skills excluded (scope discipline / wrong-repo writes / reliability).
- **Ponytail** is **embedded verbatim in the implementer's system prompt** (the ladder + rules + "not lazy about" list, full mode, active every response), sourced from `opensource/ponytail` (AGENTS.md / skills/ponytail), kept current by upstream pulls.
- **Image config**: `defaultProjectTrust: "always"` in the container's `~/.pi/agent/settings.json` so project-local resources resolve headless.

### Rationale

- Reusing the session's own model keeps cost/behavior consistent with the factory's proven choices and avoids a new dependency decision.
- Embedding ponytail converts a loadable skill into an unconditional working style — the only reliable enforcement for an autonomous worker.
- The two new skills are narrow and mechanism-friendly: implementer-ops constrains the run; implementer-save fixes save-knowledge's session-file heuristic for headless ephemeral sessions.

### Consequences

- New artifacts in the workspace root: `.pi/agents/implementer.md` (system prompt body), `.agents/skills/implementer-ops/SKILL.md`, `.agents/skills/implementer-save/SKILL.md`.
- Every implementer run traces to Langfuse, aligning the assembly line with the langfuse-agentic-operations effort.
- Model changes are config-only; skills/directive changes are repo-content-only.

### Revision triggers

- A stronger default model becomes available and the flash model proves too weak for large PRDs (acceptance stage 2 is the evidence source).
- Ponytail upstream changes its directive materially — the embedded copy must be re-synced.
- A legitimate need appears for search or another excluded skill inside the sandbox — revisit the exclusion list deliberately.