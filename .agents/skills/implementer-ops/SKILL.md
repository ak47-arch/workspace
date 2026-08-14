---
name: implementer-ops
description: Run contract for the autonomous implementer agent. Defines the exact operational protocol — read the brief, iterate story-by-story inside the worktree, run the PRD verification commands, and produce the outbox report + decisions. Use when operating as the implementer inside the sandbox.
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

- Your durable workspace is `/sandbox/worktree` — a repo clone on branch
  `factory/<slug>/<ts>` at the repo's manifest branch, mounted from host disk
  (so your edits are durable the moment you write them — no git needed).
- Run everything with `cwd=/workspace` so pi discovers the factory's skills and
  extensions (`langfuse-tracing`).
- Read the PRD (read-only under `/workspace/docs/prd-queue/`) and the target
  repo's existing conventions before writing.

## 2. Iterate story-by-story

1. Pick the next user story from the PRD (stories are independently checkable).
2. Implement it **inside `/sandbox/worktree` only**.
3. Run the story's verification (the PRD's Testing decisions / acceptance).
4. **Do NOT run any git command** (no add/commit/stash/push/pull). Your edits are
   already durable on the host via the mount. The host driver authors the
   single commit at the end.
5. If a container respawns you, your continuity is NOT lost: the driver
   reopens the SAME pi session (same `--session-id` pointing at the host mount),
   so you resume with full memory of prior turns and tools. Just keep working.

## 3. Verification protocol

- Run the PRD's verification commands inside the worktree.
- If full verification can't run in the sandbox (missing secrets/network),
  prove what can be proven (syntax check, static check, unit tests) and record
  precisely what remains for UAT in the report.
- Never skip verification silently — always state what was and wasn't verified.

## 4. Hard rules (non-negotiable)

- Modify only `/sandbox/worktree`. `/workspace` is read-only; you **cannot**
  and **must not** touch `docs/tasks/`, `docs/tasks.txt`, `docs/prd-queue/`.
- **Never run any git command** — no init/add/commit/stash/push/pull/checkout.
  The host is the sole git actor.
- No secrets, no GitHub credentials, ever.
- No push, no PR, no amend of pushed branches — the driver owns remotes.
- Do not append to `docs/knowledge/index.md` (driver-owned). Capture decisions
  to your outbox instead.
- **Verify what you build** — run the PRD's verification commands; prove what
  can be proven and record exactly what remains for UAT.
- **Say no to vanishing scope** — if a story is genuinely ambiguous or
  unresolvable without the user, implement the deterministic best
  interpretation, mark it in the report as a UAT hand-off, and move on.

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

Do not push, merge, transition, or run any git command. When you exit, the
host driver:
- hosts a single commit of your worktree changes (you never touch git),
- archives your outbox to `docs/implementations/<date>-<slug>/`,
- appends index entries deterministically (`sort-knowledge-index.py`),
- links your implementation session on the task file,
- commits + pushes the workspace root and your worktree branch, and
- raises a PR against the repo's manifest branch.
