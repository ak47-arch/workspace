# Task Traceability

This directory (`docs/tasks/`) contains one file per task — a **reference hub** that links to every artifact produced during the task's lifecycle.

## How tasks get tracked

1. **User adds a task** to `docs/tasks.txt` — that's the flat list, no change to the user's workflow.

2. **Agent picks up the task** — the agent derives a slug from the title and:
   - Appends `[<slug>]` to the end of the task's line in `docs/tasks.txt`
   - Creates `docs/tasks/<slug>.md` with status `in-prd` and a `Source` field quoting the exact line

3. **Work progresses** — the task file accumulates links to the PRD, session files, and decisions as they're created.

4. **Task completes** — the PRD moves from `docs/prd-queue/` to `docs/prd-archive/` (same filename, just moved), and the task file status updates to `complete`.

## Lifecycle states

```
open → in-prd → prd-ready → in-implementation → in-verification → complete
```

| State | Meaning |
|-------|---------|
| `open` | In `tasks.txt` but not yet picked up (no `[slug]` annotation, no task file) |
| `in-prd` | Being analysed; PRD is being drafted |
| `prd-ready` | PRD is in `docs/prd-queue/` ready for implementation |
| `in-implementation` | Implementation is active |
| `in-verification` | Testing/verification in progress |
| `complete` | Done; PRD moved to `docs/prd-archive/` |

The user marks state transitions manually. The agent updates the task file and moves artifacts accordingly.

## Task file format

```markdown
# Task: <slug>

**Status**: <state>
**Project**: <project>
**Created**: <yyyy-mm-dd>
**Completed**: <yyyy-mm-dd>  (only when complete)
**Source**: docs/tasks.txt — `<exact tasks.txt line with [slug]>`

## Artifacts

- PRD: <path>  (if created)
- ... (other artifacts)

## Sessions

- <path to session.jsonl>

## Decisions

- <path to decision file>
```

## File layout

```
docs/
├── tasks.txt                 ← flat task list (user-facing)
├── tasks/                    ← task reference hubs
│   ├── README.md
│   └── <slug>.md
├── prd-queue/                ← PRDs ready for implementation
│   └── <yyyy-mm-dd>-<slug>.md
├── prd-archive/              ← completed PRDs (same filename)
│   └── <yyyy-mm-dd>-<slug>.md
└── knowledge/
    └── sessions/
        └── <uuid>/
            ├── session.jsonl
            └── decisions/
                ├── <sequence>-<slug>.md
                └── ...
```

## Traceability chain

- `tasks.txt` line → `[slug]` → `docs/tasks/<slug>.md`
- `docs/tasks/<slug>.md` → links to PRD, sessions, decisions
- Every PRD and decision file has a `**Task**: <slug>` field in its header
- Grep `Task: <slug>` across `docs/` to find every artifact for a task
- Grep `[<slug>]` in `docs/tasks.txt` to find the originating task entry