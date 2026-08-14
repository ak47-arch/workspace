# Task: implementer-ponytail

**Status**: in-progress
**Category**: Small
**Project**: software-factory
**Created**: 2026-08-14 00:45
**Source**: docs/tasks.txt — `Integrate the real ponytail skills into the implementer agent via pi --skill flags, replacing the prose directive (software-factory) [implementer-ponytail]`

## Artifacts

- Plan: (not yet created)

## Context

The implementer persona (`.pi/agents/implementer.md`) embeds ponytail only as a
hand-written prose directive ("Working style: ponytail (always-on directive)") —
never wired to the real skill package at `opensource/ponytail/skills/`. This task
upgrades it to the actual skills via the same repeatable `--skill` flag mechanism
the code-review agent uses (see decision 04 in session
`019ff79e-181d-7e8b-a869-398b6417d28a`).

## Sessions

- (planning not yet captured)
- [implementation](../knowledge/sessions/8483b243-ad9a-4e00-be82-0cdf26a8801d/session.jsonl)

## Decisions

- (none yet)- [ponytail-review-worker-skills](../knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/04-ponytail-review-worker-skills.md)

## PR tracking

- PR: #2 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/2
- Branch: factory/implementer-ponytail/20260814-212431
- Base: master · Head: 212370c67833ace883e263a17941a1f2f80e84d7 (raised 2026-08-14 21:40)
- Raised by: implementer run 8483b243-ad9a-4e00-be82-0cdf26a8801d
