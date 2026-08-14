# Task: implementer-revision-mode

**Status**: in-progress
**Category**: Medium
**Project**: software-factory
**Created**: 2026-08-14 22:13
**Source**: docs/tasks.txt — `Add an implementer revision mode (--revise <pr>) that resumes the original implementation session to address reviewer findings, injecting the review report as binding authority (software-factory) [implementer-revision-mode]`

## Artifacts

- Plan: (not yet created)

## Context

Decision 08 (`docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/08-implementer-revision-same-session.md`)
established that review-feedback fixes are made by the **implementer resuming
its original implementation session** — not by the operator hand-editing the
branch, and not by a fresh implementer session. Today `bin/implementer-run.sh`
has no such mode: it raises a fresh PR per task, and `--resume` is reserved but
unimplemented.

The first real REQUEST_CHANGES cycle (implementer-ponytail PR #2, review
`docs/code-reviews/2026-08-14-implementer-ponytail/report.md`) is the first
target for this mode.

## Sessions

- (planning not yet captured)
- [implementation](../knowledge/sessions/cb6a90c1-f8d0-4da5-b413-1f82a0f32376/session.jsonl)

## Decisions

- `docs/knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/08-implementer-revision-same-session.md`

## PR tracking

- PR: #3 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/3
- Branch: factory/implementer-revision-mode/20260814-223839
- Base: master · Head: 223b2bde8ed28c3e36f81228862a128eedf9fbfe (raised 2026-08-14 23:22)
- Raised by: implementer run cb6a90c1-f8d0-4da5-b413-1f82a0f32376
