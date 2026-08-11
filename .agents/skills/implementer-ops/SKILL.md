---
name: implementer-ops
description: Run contract for the autonomous implementer agent. Defines the exact operational protocol — read the brief, iterate story-by-story with commit-early inside the worktree, run the PRD verification commands, and produce the outbox report + decisions. Use when operating as the implementer inside the sandbox.
---

# Implementer Ops — Run Contract

This is the operational contract for the **implementer agent** running headless
inside the sandbox container (the "hands" side). The host driver owns all git
mutations, push, PR, and lifecycle bookkeeping. You own the creative work in
the worktree and the outbox artifacts. Follow this contract exactly.

## 0. Read your brief first

Read `/sandbox/brief.md` before anything else. It carries the PRD path, task
slug, implementation-session UUID, worktree path, outbox paths, and binding
rules. The brief is authoritative for *this run*.

## 1. Orient in the worktree

- Your durable workspace is `/sandbox/worktree` — a git worktree on branch
  `factory/<slug>/<ts>` at the repo's manifest branch.
- Run everything with `cwd=/workspace` so pi discovers the factory's skills and
  extensions (`langfuse-tracing`).
- Read the PRD (read-only under `/workspace/docs/prd-queue/`) and the target
  repo's existing conventions before writing.

## 2. Iterate story-by-story, commit-early

1. Pick the next user story from the PRD (stories are independently checkable).
2. Implement it **inside `/sandbox/worktree` only**.
3. Run the story's verification (the PRD's Testing decisions / acceptance).
4. `git -C /sandbox/worktree add -A && git -C /sandbox/worktree commit -m "story(N): <description>"`
5. Repeat. A fresh commit per story is your only durable memory — a container
   respawn resumes from your last committed state.

## 3. Verification protocol

- Run the PRD's verification commands inside the worktree.
- If full verification can't run in the sandbox (missing secrets/network),
  prove what can be proven (syntax check, static check, unit tests) and record
  precisely what remains for UAT in the report.
- Never skip verification silently — always state what was and wasn't verified.

## 4. Hard rules (non-negotiable)

- Modify only `/sandbox/worktree`. `/workspace` is read-only; you **cannot**
  and **must not** touch `docs/tasks/`, `docs/tasks.txt`, `docs/prd-queue/`.
- No secrets, no GitHub credentials, ever.
- No push, no PR, no amend of pushed branches — the driver owns remotes.
- Do not append to `docs/knowledge/index.md` (driver-owned). Capture decisions
  to your outbox instead.

## 5. Finish — the outbox contract

Produce, in `/sandbox/outbox/`:

### `report.md`
Per **user story**: `done` / `not-done` + evidence (what changed, where).
Then:
- **Verification results**: what ran, what passed/failed, what remains for UAT.
- **UAT hand-off list**: anything the user must inspect/approve.
- **Decisions emerged**: list of any decision files written to
  `outbox/decisions/`.

### `decisions/NN-<slug>.md`
For each design decision that emerged, a structured decision file in the
standard knowledge format (`## Decision`, `**Status**`, `**Date**`,
`**Task**`, `**Project**`, `**Session**`, Context / Problem / Alternatives /
Decision / Rationale / Consequences / Revision triggers). Use the
`implementer-save` skill to do this correctly — it passes your session
directory explicitly.

Then exit 0 (success) or exit 1 (partial report / blocker). The driver reads
the outbox either way.

## 6. Hand-off to the driver

Do not push, merge, or transition anything. When you exit, the driver:
- archives your outbox to `docs/implementations/<date>-<slug>/`,
- appends index entries deterministically (`sort-knowledge-index.py`),
- links your implementation session on the task file,
- commits + pushes the workspace root and your worktree branch, and
- raises a PR against the repo's manifest branch.
