# Implementer Report — task-pickup-similarity-merge

- **Task slug**: task-pickup-similarity-merge
- **Impl session**: b77c5e2b-a870-40c7-bcad-effcbc45332a
- **PRD**: `docs/prd-queue/2026-08-17-task-pickup-similarity-merge.md`
- **Worktree**: `/sandbox/worktree`

## Per-story status

| # | Story | Status | Evidence |
|---|-------|--------|----------|
| 1 | **Merge proposal** — show similar Pending/Queued task with one-line "why" and ask to pick together | done | New `### 2. Similarity check` subsection in `.agents/skills/product-layer/SKILL.md` (inside `### 1. Read the model`, after pick-up, before slug/categorise). Specifies scanning every line/project/status, match classes, and the one-line "why" proposal. |
| 2 | **Degree of similarity** — full / partial / none, user-confirmed response (merge / split / proceed) | done | Same subsection: full → merge, partial → split, none → proceed single. Explicit "always user-confirmed, never automatic". |
| 3 | **Partial split** — overlap joins bundle; remainder written as new Pending line in `docs/tasks.txt`, clarified wording, no slug | done | Same subsection: remainder registered as new Pending line under its own project, no slug, original line stays verbatim. |
| 4 | **Informational flags** — in-progress/in-review → "already being worked on", Complete → "appears to already be done", never a merge offer | done | Same subsection: **Status policy** block. Merge offers restricted to Pending/Queued. |
| 5 | **One bundle, one PRD** — all lines same `[slug]`, task file `Source` lists every line, one PRD | done | `### 3. Slug, categorise, annotate` subsection + task-file template `Source` field updated to comma-separated list of verbatim lines. Bundle category = max of constituents (decision 08). |
| 6 | **Bundles close all their lines** — transition moves every `[slug]` line to its own project's status section, no stranded lines | done | `bin/transition-task.sh` tasks.txt Python block rewritten to collect ALL `[slug]` lines and move each to its own project section (`## all` stays under `## all`). Verified by new multi-line test + end-to-end dry-run demo of the langfuse trio. |
| 7 | **Silent when nothing matches** — pick-up proceeds as today, no ceremony | done | Same subsection: "**Silent when nothing matches**" paragraph. |

## Verification results

### Deterministic — transition script

- Ran `bash bin/test-transition-task.sh` inside the worktree → **54 passed, 0 failed**.
  - **New multi-line test** (`test_multi_line_bundle`): 3 lines sharing one `[slug]` (one under `## all`, two under `## test-project`), transition to `complete`. All 3 assert on: moved to Complete with `(complete)` prefixes, none stranded in Pending, and each landed in **its own project's** Complete section.
  - **Single-line regression**: all 13 pre-existing tests (basic complete, prd-ready, sessions/decisions, invalid state, missing file, idempotency, dry-run, PRD archive, special chars, etc.) still pass unchanged.
- `bash -n bin/transition-task.sh` and `bash -n bin/test-transition-task.sh` → syntax OK.
- **End-to-end dry-run demo** mirroring the exact langfuse scenario: a bundle with one line under `## all` and two under `## langfuse` → dry-run produced `## all/Complete` containing the `(complete)` all-line and `## langfuse/Complete` containing both `(complete)` langfuse lines; no lines remain in Pending. Matches the PRD's known-edge expectation.

### Behavioural — skill flow (UAT)

The product-layer skill is a procedural spec; its acceptance is a behavioural walkthrough in a real session. Not testable in the sandbox. See UAT hand-off below.

## UAT hand-off list

1. **Skill flow walkthrough** (PRD Testing decision 3): in the next real product-layer session, pick a task with a known similar task and verify the candidate proposal with "why", the degree-of-similarity conversation, and (on acceptance) one slug across lines, a multi-source task file, and one PRD.
2. **First real multi-line transition** (PRD Further notes): the langfuse task (`langfuse-agentic-operations`) is `in-prd` with 3 annotated lines and has never been transitioned. Its first transition (to `prd-ready`) will exercise the multi-line fix for real — confirm all 3 lines move (one stays under `## all`, two under `## langfuse`).
3. **CONTEXT.md glossary**: the PRD suggested adding "merge bundle" and "degree of similarity" to `CONTEXT.md`. `CONTEXT.md` lives at the workspace root (outside the worktree) and is not present in the worktree mount, so I could not edit it. Instead I added both terms to the skill's `## Glossary` section (`.agents/skills/product-layer/SKILL.md`). If `CONTEXT.md` is expected to carry the shared vocabulary, copy the two terms there.
4. **Note on `--dry-run`**: the PRD's multi-line test mentions `--dry-run`, but the test harness runs inside an isolated temp workspace (not a git repo, so no commit occurs), so I followed the existing test convention of running without `--dry-run` so assertions can read the resulting temp files. The separate end-to-end demo was run with `--dry-run` to confirm real files are untouched.

## Decisions emerged

- `outbox/decisions/01-pickup-similarity-merge.md` — single-line tasks keep the task file's declared project for relocation; only multi-line bundles use each line's own enclosing project section.

## Files changed

- `bin/transition-task.sh` — multi-line `[slug]` relocation in the tasks.txt update step.
- `bin/test-transition-task.sh` — new `test_multi_line_bundle` test + `write_multi_tasks_txt` fixture.
- `.agents/skills/product-layer/SKILL.md` — similarity-check flow (stories 1–5, 7), bundle categorisation, task-file template `Source` field, and glossary terms.
