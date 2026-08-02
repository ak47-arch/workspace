## Decision: Task Lifecycle State Machine and Transition Tooling

**Status**: accepted
**Date**: 2026-08-01 16:36
**Task**: task-file-dashboard
**Project**: software-factory
**Session**: sessions/019fb98c-22b4-7a11-8ef5-fc3baa6634c0/session.jsonl

### Context

The task dashboard (`docs/tasks.txt` + `docs/index.html`) allows adding tasks from a phone via the web. This creates a new workflow: tasks can be added remotely, but when the user returns to their local workspace, the file is stale. The product-layer skill had no "sync" step, so sessions started with outdated data.

More broadly, when a task was completed, the bookkeeping was manual and often missed:
- The task file's `Sessions` and `Decisions` sections stayed empty
- The task line in `tasks.txt` was never moved to the `Complete` section
- The PRD was never moved from queue to archive

As the factory grows, tasks will have multi-stage lifecycles (PRD → Implementation → Verification), each producing its own session and decisions. The manual approach won't scale.

### Problem

1. No automated mechanism to sync the workspace before a session (`git pull`)
2. No automated mechanism to update task lifecycle metadata after a session (task file, tasks.txt, PRD archive)
3. No defined state machine for task lifecycle — states were informal and inconsistent
4. No enforcement — the agent could forget or skip bookkeeping steps

### Alternatives

1. **Manual convention only** — add instructions to the skill but no tooling. Rejected because it would be forgotten again.

2. **A dedicated monitoring agent** — an agent that watches for task completions and updates bookkeeping. Rejected as too complex for the current scale; introduces a new agent to manage.

3. **A CLI tool (`bin/transition-task.sh`)** — a single-purpose script that handles the mechanical bookkeeping. Chosen because it's simple, deterministic, and callable from any skill.

4. **Git hooks** — automatically run bookkeeping on certain git operations. Rejected because the bookkeeping is session-driven, not git-driven; a hook would fire at the wrong time.

### Decision

Adopt a **state machine + CLI tool** approach:

- **Task lifecycle states**: `in-prd` → `prd-ready` → `in-progress` → `in-review` → `complete`, each mapping to a `tasks.txt` status section (Pending/Queued/Complete).
- **`bin/transition-task.sh`** — a shell script that:
  1. Updates the task file (`docs/tasks/<slug>.md`) with new status, date, session links, and decision links
  2. Moves the task line in `docs/tasks.txt` to the correct status section
  3. Archives the PRD from `docs/prd-queue/` to `docs/prd-archive/` (when transitioning to `complete`)
  4. Commits the changes
- **`git pull` at session start** — added to the product-layer skill's "Before you begin" section as step 0.

### Rationale

- The CLI tool is the same pattern as `save-knowledge` — a single-purpose script that does one well-defined bookkeeping operation
- The state machine gives explicit vocabulary for lifecycle transitions, which is needed as the factory grows to handle multi-stage tasks
- The tool is callable from any skill (product-layer, assembly-line, verification) and enforces the rules uniformly
- Git pull at session start is a one-line change to the skill that prevents the most common failure mode

### Consequences

- Skills must be updated to call `bin/transition-task.sh` in their finalise steps instead of doing manual bookkeeping
- The task file format becomes a stable contract — all skills depend on it
- A new tool means one more thing to maintain, but the logic is simple and well-bounded
- The `tasks.txt` format (indentation, section headers) becomes a de facto data format that the tool depends on

### Revision triggers

- If task lifecycle needs to support more complex workflows (e.g., parallel tracks, rejection loops)
- If the `tasks.txt` format changes significantly
- If the factory outgrows a single script and needs a proper task management system
- If multi-user collaboration creates merge conflicts in `tasks.txt`