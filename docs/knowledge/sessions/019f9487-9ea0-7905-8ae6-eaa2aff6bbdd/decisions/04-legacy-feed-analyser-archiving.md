## Decision: Legacy feed_analyser archiving

**Status**: accepted
**Date**: 2026-07-25
**Project**: feed-analyser
**Session**: sessions/019f9487-9ea0-7905-8ae6-eaa2aff6bbdd/session.jsonl

### Context

The feed_analyser application was a failed product. The user identified it as such: the only used feature was the Twitter ingestion pipeline. The dashboard, GitHub scout, knowledge graph, workbench, and all other features were unused. The application was over-engineered for its actual usage (5,979 lines of code, 5 Docker containers, 13 specs, all serving one user who only used the ingestion step).

### Problem

The old code and data need to be handled in a way that:
1. Clears the way for the new capture system without confusion between old and new.
2. Preserves the existing data (~1,200 tweets in SQLite) and code for reference.
3. Does not delete anything — the user explicitly said "don't delete anything."
4. Keeps git history intact.

### Alternatives

1. **Delete the old code** — rejected. User explicitly said don't delete anything. Data and code may be useful for reference.
2. **Create a new repo** — rejected. User chose to keep everything in the same `feed_analyser` repo. The repo name no longer describes what it does, but this was accepted.
3. **Move old code to `archive/` inside the repo** — chosen. Everything physically moves to `archive/` so the root is clean for the new `capture/` directory. Git history is preserved via `git mv`.

### Decision

- All old code, docs, specs, configs, docker-compose, scripts, and data moved into `feed_analyser/archive/` via `git mv`.
- `archive/` contains everything that was at the root: `backend/`, `frontend/`, `scripts/`, `specs/`, `docs/`, `config/`, `openwiki/`, `graphify-out/`, `docker-compose.yml`, `start.sh`, `vision.md`, `CHANGELOG.md`, etc.
- New code goes into `capture/extension/` and `capture/server/`.
- The old data (`archive/backend/data.db`, 856KB) stays in place — accessible to future backend apps.
- The `.gitignore` was updated to reflect the new structure.

### Rationale

Archiving inside the same repo keeps everything accessible without cluttering the workspace root. Git mv preserves history — every old commit is still reachable. The separation is physical (different directories) but the repo history is linear and clean.

### Consequences

- Old feed_analyser code is no longer operational unless explicitly run from the archive path.
- Existing OpenWiki links in `factory-context.md` now point to `archive/openwiki/` — no longer at the expected path.
- Future backend apps can read from both `archive/backend/data.db` (old) and `artefacts.jsonl` (new) without any migration work.
- The repo name (`feed_analyser`) is now a misnomer — it houses `capture/`, not a feed analyser. Renaming the repo is a separate decision.

### Revision triggers

- If the old code in `archive/` is never referenced for months or years, it could be pruned (but the user said don't delete, so this would need explicit user consent).
- If the repo name becomes confusing for collaborators or future work, consider renaming the repo.
- If the old SQLite data is migrated to the new storage format, the `archive/backend/data.db` can be removed from the repo (but kept in git history).