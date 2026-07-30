# Task: vision-task-traceability

**Status**: complete
**Project**: software-factory
**Vision**: docs/vision-convention.md
**Created**: 2026-07-30
**Completed**: 2026-07-31
**Source**: docs/tasks.txt — `(complete) add more clarity to the knowledge base by connecting the vision to the tasks and the end to end tracing of everything (software_factory)(top priority) [vision-task-traceability]`

## Summary

This task established the **upstream traceability link** in the progressive disclosure chain. The downstream link (task → PRD → sessions → decisions) was already handled by the `end-to-end-traceability` task. This task completed the full chain: **vision → tasks → PRDs → sessions → decisions**.

## Sub-tasks

### C — Add `Project:` field to decision entries
- Updated `save-knowledge` skill template with `**Project**: <slug>` field
- Backfilled all 21 existing decision files with the correct project slug
- Reorganized `docs/knowledge/index.md` into project-grouped sections

### A — Define vision doc convention
- Wrote `docs/vision-convention.md` defining:
  - Path convention: `<project>/docs/vision/VISION.md` + optional `TECHNICAL_VISION.md`
  - Standard 9-section format
  - Three-way linking: Vision→Tasks (`## Active Tasks`), Tasks→Vision (`**Vision**:`), PRDs→Vision (`**Vision**:`)
  - When to write and how to maintain vision docs
- Updated `docs/factory-context.md` Vision table with status column

### B — Write vision docs for highest-value projects
- `feed_analyser/capture/docs/vision/VISION.md` — capture instrument vision
- `llm/docs/vision/VISION.md` — LLM inference server & client vision
- Updated PRD headers with `Project:` and `Vision:` fields

## Artifacts

- Convention: docs/vision-convention.md
- Vision (capture): feed_analyser/capture/docs/vision/VISION.md
- Vision (llm): llm/docs/vision/VISION.md

## Sessions

- docs/knowledge/sessions/019fb45b-9f0f-79e2-ac55-a0a084ac3156/session.jsonl

## Decisions

- docs/knowledge/sessions/019fb45b-9f0f-79e2-ac55-a0a084ac3156/decisions/01-vision-document-convention.md