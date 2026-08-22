# Task: typed-trail-integrity

**Status**: in-progress
**Category**: Medium
**Project**: software-factory
**Created**: 2026-08-22
**Source**: docs/tasks.txt — `Make the disclosure trail machine-followable: typed links, stable PRD home, decision read-skip (software-factory) [typed-trail-integrity]`

## Artifacts

- Plan: `docs/prd-queue/2026-08-22-typed-trail-integrity.md`

## Progress

## Change

Merge signals 01 + 04 + 05 into one coherent fix for the "trail isn't machine-checkable"
disease: (a) PRDs live at a stable `docs/prd/` home with lifecycle state as a routing-manifest
status field (direction C), (b) cross-references are typed relative links resolved from the
artifact's own location, with front-matter `Task`/`Session`/`Decisions` signed to links and
`Status` linking to the manifest row, and (c) every decision file carries a `**Summary**:`
read-skip line. Retrospective tooling keeps a single home; `resolve_prd() --pick` ordering is
preserved. This is the typed-trail backbone the context-disclosure semantic probe grades
against.

## Decisions

- (record per session)

## Phase tasks
1. **Probe contract / manifest schema**: pin `docs/prd/manifest.json` (slug → status + ordering-key)
2. **Migration**: one-time `git mv` all archived PRDs to `docs/prd/`, fix inbound links, add manifest
3. **Link/front-matter signing**: convert PRD/decision/reference string paths to typed relative links; sign front-matter `Task`/`Session`/`Decisions`; `Status` → manifest row
4. **Read-skip summary backfill**: add `**Summary**:` to 113 decision files (7→120)
5. **Hygiene extension**: add the three typed-trail checks to `bin/eval-hygiene.py` (string-path, summary-presence, stale/mismatch) with demonstrated injection flips
6. **Ordering regression**: confirm `resolve_prd() --pick` still returns oldest `Final`+`prd-ready`
## Sessions

- [implementation](../knowledge/sessions/05f805ea-0bae-44f3-9791-93fc9cb43639/session.jsonl)

## PR tracking

- PR: #46 (ak47-arch/workspace) — OPEN · only review, never merges
