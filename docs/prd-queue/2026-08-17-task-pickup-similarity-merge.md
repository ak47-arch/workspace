# PRD: Task-pickup similarity check and merge flow

**Date**: 2026-08-17 01:29
**Status**: Draft
**Owner**: software-factory workspace
**Task**: task-pickup-similarity-merge
**Session**: `docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/decisions/01-task-similarity-check-scope.md`
  - `docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/decisions/02-semantic-similarity-assessment.md`
  - `docs/knowledge/sessions/357a4c1d-cfd2-47d4-b3a8-a831dd310daf/decisions/03-partial-split-remainder-registration.md`

## Problem statement

When a user picks a task from `docs/tasks.txt`, that task frequently already exists in another form — reworded in the same project, or as the same capability across projects. The canonical example is the langfuse trio: `integrate langfuse with all applications` (all), `integrate official langfuse skill` (langfuse), and `set up langfuse use and operation agentically` (langfuse) all converge on one goal and were merged into the single `langfuse-agentic-operations` task by hand.

Today the product-layer skill has **no similarity detection at pick-up time**. Consequences:

1. **Missed merges** — related tasks stay scattered in the list, get picked up in separate sessions, and produce separate PRDs and separate implementation runs for what is one coherent goal.
2. **Duplicate entries** — the same intent gets filed again because nobody notices an existing line (possibly under another project).
3. **No clarity loop** — tasks that are only *partially* similar are never decomposed; the user is forced into an all-or-nothing choice that doesn't exist in the current skill.
4. **Merging is half-implemented** — a merged bundle exists (langfuse: 3 task lines sharing one `[slug]`), but `bin/transition-task.sh` moves only the **first** `[slug]` line on transition. The other two lines would be stranded in Pending when the task moves to Queued/Complete — so a merged task cannot actually close all its source lines.

## Solution overview

Add a **similarity-check step** to the product-layer skill's pick-up flow. When the user picks a task (from the list or freshly entered), the agent scans all task lines across all projects and statuses, proposes candidate similar tasks with a one-line "why" for each, and works with the user to establish the **degree of similarity**:

- **Full** → merge into one task file + one PRD, closed together (existing convention: one `[slug]` annotated on all chosen lines, task file `Source` field lists each line).
- **Partial** → divide the picked task: the overlapping part joins the bundle; the remainder is registered as a new Pending line in `docs/tasks.txt` (no slug — it earns one at pick-up, like every other pending task).
- **None** → proceed with the single task, exactly as today.

In-progress / in-review / Complete matches are informational flags only — never merge offers. No scoring, no embeddings, no thresholds: the agent's semantic judgment, always user-confirmed.

To make merging work end-to-end, extend `bin/transition-task.sh` to move **all** lines annotated with `[slug]` (each within its own project section) instead of only the first.

## User stories

1. **Merge proposal.** When I pick a task and a Pending/Queued task in any project is similar (near-duplicate, same subject, or same capability across projects), the agent shows me the match with a one-line "why" and asks whether to pick them together.
2. **Degree of similarity.** For each proposed candidate I can assess the degree — full, partial, or none — and the agent responds accordingly (merge, split, or proceed single).
3. **Partial split.** When a task is only partially similar, the agent works with me to divide it: the overlapping part joins the bundle, and the remainder is written as a new Pending line in `docs/tasks.txt` with clarified wording and no slug.
4. **Informational flags.** When a similar task is in-progress, in-review, or Complete, the agent flags it as informational ("already being worked on" / "appears to already be done") and never offers a merge.
5. **One bundle, one PRD.** When I accept a merge, all chosen lines get the same `[slug]`, the task file's `Source` field lists every line, and one PRD covers the bundle.
6. **Bundles close all their lines.** When a merged task transitions (e.g. to `complete`), every task line annotated with its `[slug]` moves to the target status section within its own project — no stranded lines.
7. **Silent when nothing matches.** When no similar tasks exist, pick-up proceeds exactly as today — no added ceremony, no delay.

## Implementation decisions

1. **Where the check runs.** In `.agents/skills/product-layer/SKILL.md`, immediately after the user picks a task (or enters a new one), *before* slug derivation and categorisation — the merge decision can change which tasks the slug attaches to. The new subsection lives in "### 1. Read the model", replacing the current single-task pick-up block with a pick-up → similarity-check → slug/categorise flow.
2. **What the agent scans.** All task lines in `docs/tasks.txt`, all projects, all statuses. Match classes: near-duplicate (same intent, reworded), same subject different framing, cross-project capability. Each proposal carries a one-line "why" so the user can veto quickly.
3. **Status policy (decision 01).** Merge offers only for Pending/Queued. In-progress/in-review → "already being worked on". Complete → "appears to already be done". No merge in either case.
4. **Degree of similarity (decision 02).** Established collaboratively with the user. Full → merge; Partial → split; None → proceed. No automatic merging — always user-confirmed.
5. **Partial-split remainder (decision 03).** Remainder written as a new Pending line in `docs/tasks.txt` under its project, clarified wording, no slug. Original picked-task line stays verbatim (tasks.txt preserves original lines); clarity lives in the task file and PRD.
6. **Merged task file template.** The task file template's `Source` field becomes a comma-separated list of the verbatim task lines (matching the langfuse task file convention), so downstream traceability keeps working.
7. **Transition script multi-line fix.** In `bin/transition-task.sh`, the tasks.txt update step collects **all** lines containing `[slug]` and moves each to the target status section **of its own project section** (lines under `## all` stay under `## all`), rather than finding only the first line and relocating it to the task file's declared project. Behaviour for single-line tasks is unchanged.
8. **Category of a bundle.** The bundle's category is the max of its constituents' categories (a Small + a Medium → Medium), so planning depth matches the largest member.

## Testing decisions

Seam: the skill document is a procedural spec, so verification is a mix of script tests and a behavioural walkthrough.

1. **Transition script (deterministic).** Extend `bin/test-transition-task.sh` with a multi-line fixture: a `tasks.txt` with 3 lines sharing one `[slug]` (one under `## all`, two under `## <project>`), run `bin/transition-task.sh <slug> --to complete --dry-run`, and assert all 3 lines end up in their own project's Complete section with `(complete)` prefixes, and none remain in Pending.
2. **Single-line regression.** The existing transition tests must keep passing unchanged — the multi-line fix must not alter single-line behaviour.
3. **Skill flow (behavioural).** In the next real product-layer session, pick a task with a known similar task and verify: candidate proposal with "why", degree-of-similarity conversation, and (on acceptance) one slug across lines, multi-source task file, and one PRD. This is the user-acceptance test for the skill change itself.

## Out-of-scope items

- **No dashboard/UI changes** — the remote task dashboard renders `docs/tasks.txt`; the similarity check lives in the agent, not the dashboard.
- **No embeddings / fuzzy-match infrastructure** — semantic judgment by the agent, per decision 02.
- **No automatic merging** — always user-confirmed.
- **No re-check of the remainder within the same session** — the leftover line is checked when it is picked up later.
- **No changes to the implementer/reviewer agents** — they already consume one task file + one PRD per bundle.
- **No changes to the langfuse bundle itself** — the multi-line fix is verified by tests, not by force-transitioning the langfuse task.

## Further notes

- **Known edge to watch.** The langfuse task (`langfuse-agentic-operations`) is currently `in-prd` with 3 annotated lines and has never been transitioned. Its first transition (to `prd-ready`) will exercise the multi-line fix for real — worth confirming then that all 3 lines move.
- **Verbatim lines convention.** `docs/tasks.txt` preserves original task lines verbatim; the similarity conversation may *reword* a task, but rewrites of existing lines are not part of this task — clarified wording goes into new remainder lines, the task file, and the PRD.
- **Glossary.** "Merge bundle" (a set of task lines sharing one `[slug]`, one task file, one PRD) and "degree of similarity" (full / partial / none) are new vocabulary — consider adding to `CONTEXT.md` during implementation.
