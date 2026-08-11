---
name: implementer-save
description: Scoped decision capture for the autonomous implementer agent. Writes structured decision records into the implementer's outbox with an explicitly-passed session directory (the driver knows the implementation-session UUID). The driver — never the model — appends the index entry. Use when a design decision emerges during an implementation run inside the sandbox.
---

# Implementer Save — Scoped Decision Capture

The `save-knowledge` skill finds the current session by scanning `~/.pi/agent`
for the most recently modified JSONL — but the implementer runs **headless**
(`--mode json --no-session`), so that heuristic is blind. This skill replaces
it inside the sandbox: you are given the session directory explicitly, and you
write decisions to your **outbox** rather than committing directly to the
knowledge base (which lives in the read-only `/workspace` mount).

## When to use

When a real design decision emerges during implementation (an architectural
choice, a rejected alternative, a trade-off worth recording) — same trigger as
the regular `save-knowledge` skill, but adapted to the sandbox's constraints.

## Session directory

The driver writes your implementation-session UUID into
`/sandbox/brief.md` as **Impl session UUID**. Your session directory (host-side,
mounted into the container as part of the run dir) is
`/sandbox/session` — that is where configuration/locator state for this run
lives. Decisions themselves are written to `/sandbox/outbox/decisions/` so the
driver can archive them after the run.

## Workflow

1. **Read `/sandbox/brief.md`** for the task slug, project, and session UUID.

2. **Derive the title and slug** from the decision, same as `save-knowledge`
   (short descriptive title; hyphenated slug).

3. **Determine the next sequence number** — list
   `/sandbox/outbox/decisions/`. If empty, start at `01`; else increment the
   highest numeric prefix. Use the *global* number the driver will collate
   with — prefix `NN-` where NN is your next sequence.

4. **Write the decision** to `/sandbox/outbox/decisions/NN-<slug>.md` using
   the standard structured format:

   ```markdown
   ## Decision: <title>

   **Status**: proposed | accepted
   **Date**: <yyyy-mm-dd HH:MM>
   **Task**: <task-slug>
   **Project**: <project-slug>
   **Session**: sessions/<impl-uuid>/session.jsonl

   ### Context
   ### Problem
   ### Alternatives
   ### Decision
   ### Rationale
   ### Consequences
   ### Revision triggers
   ```

5. **Do NOT touch `docs/knowledge/index.md`.** It lives in the read-only
   `/workspace` mount and is driver-owned. The driver reads your outbox
   decision and appends the index entry deterministically via
   `sort-knowledge-index.py` after the run.

6. **List the decision** in your `report.md` under "Decisions emerged" so the
   driver + reviewer can find it.
