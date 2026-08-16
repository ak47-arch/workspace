# Code Review

- Reviewed: ak47-arch/workspace#5 (repo: ak47-arch/workspace, PR #5)
- Task: task-pickup-similarity-merge · PRD: docs/prd-queue/2026-08-17-task-pickup-similarity-merge.md · Review session: f7ba9273-8985-4ba6-b63e-e8571f6a691b
- Base: 37ef8ab499397ce8fbf5c2dcac406d868a4721ff → Head: 1cfc3695feea48d54adcde066d4a54b0cedfa655

## Verdict
APPROVE — all 7 user stories implemented and verified (deterministic transition tests pass 54/54, dry-run verified manually), no blocking findings. Only advisory notes on section placement vs the PRD's literal wording and one over-engineering micro-opportunity.

## Verification results

- **PRD Testing 1 (transition multi-line):** RAN. `bash bin/test-transition-task.sh` → **54 passed, 0 failed**. New `test_multi_line_bundle` (bin/test-transition-task.sh:394) asserts all 3 `[bundle-task]` lines (1 under `## all`, 2 under `## test-project`) land in their own project's Complete with `(complete)` prefixes and none strand in Pending.
- **PRD Testing 2 (single-line regression):** RAN. All 13 pre-existing tests (basic complete, prd-ready, sessions/decisions, invalid state, missing file, idempotent rerun, dry-run no-changes, PRD archive, special chars, etc.) pass unchanged.
- **PRD suggested `--dry-run` command:** manually exercised — `bin/transition-task.sh bundle-task --to complete --session <uuid>:planning --dry-run` on a `## all` + `## test-project` fixture → exit 0; temp tasks.txt shows `## all/Complete` with `(complete) cross project task` and `## test-project/Complete` with both `(complete)` bundle lines; real file untouched.
- **Syntax:** `bash -n bin/transition-task.sh` and `bash -n bin/test-transition-task.sh` → OK.
- **PRD Testing 3 (skill flow, behavioural):** DEFERRED — the product-layer skill is a procedural spec; acceptance is a real-session walkthrough, not runnable in the sandbox. Handed to UAT.

## Story-by-story

- [PASS] US1 **Merge proposal** — `.agents/skills/product-layer/SKILL.md` new `### 2. Similarity check` (line 35): scans every line/project/status, three match classes, one-line "why" proposal. Evidence: SKILL.md diff hunk.
- [PASS] US2 **Degree of similarity** — same section: Full→merge / Partial→split / None→proceed, "always user-confirmed, never automatic". Evidence: SKILL.md:38-45.
- [PASS] US3 **Partial split** — same section: remainder written as new Pending line under its own project, clarified wording, no slug, original line stays verbatim. Evidence: SKILL.md:41-43.
- [PASS] US4 **Informational flags** — same section **Status policy**: in-progress/in-review → "already being worked on", Complete → "appears to already be done", never a merge offer. Evidence: SKILL.md:44-49.
- [PASS] US5 **One bundle, one PRD** — SKILL.md `### 3. Slug, categorise, annotate` (line 56): one slug for the bundle, `[<slug>]` appended to every chosen line; task-file `Source` field now a comma-separated list of verbatim lines (SKILL.md:79-80). Bundle category = max of constituents (SKILL.md:68-69).
- [PASS] US6 **Bundles close all their lines** — bin/transition-task.sh Python block rewritten to collect ALL `[slug]` lines via `project_of()` and relocate each to its own project's target section. Verified by test_multi_line_bundle + manual dry-run (all 3 lines moved, none stranded).
- [PASS] US7 **Silent when nothing matches** — SKILL.md:50-51 "**Silent when nothing matches**… no added ceremony, no delay."

## Deterministic checks

- [PASS] D1 **PR metadata sane** — branch/head are a well-formed factory PR; commit `1cfc369` "implementer(task-pickup-similarity-merge): run b77c5e2b… [factory]"; base/head SHAs resolve; diff non-empty (3 files, +184/−83) and scoped.
- [PASS] D2 **Worktree clean / read-only** — `git status`: clean, HEAD detached at 1cfc369; reviewer made no changes.
- [PASS] D3 **Scope containment** — only `.agents/skills/product-layer/SKILL.md`, `bin/transition-task.sh`, `bin/test-transition-task.sh` changed; all within PRD scope. No out-of-scope edits, stray deps, or unrelated refactors.
- [PASS] D4 **Scope ⊆ PRD file-map** — all promised changes present (skill flow + transition multi-line fix + test); nothing promised is missing. PRD lists no explicit file tree; the 3-file set matches the implementation decisions.
- [PASS] D5 **Story → diff coverage** — every US (1–7) maps to a diff hunk/file (see story evidence); diff adds no capability no story asks for.
- [PASS] D6 **No secrets / stray deps** — diff scan for keys/tokens/`.env`/private keys clean; no new dependencies added.
- [PASS] D7 **Implementer report matches diff** — `docs/implementations/2026-08-17-task-pickup-similarity-merge/report.md` claims (7 stories, multi-line test, single-line regression, dry-run demo, glossary) all match the actual diff; decision `01-pickup-similarity-merge.md` matches the single-line/bundle relocation logic in code.

## Judgment checks

- [PASS] J1 **Story intent** — observable behavior described by each story would work from the diff; multi-line transition proven by test + dry-run; skill sections provide the procedural flow.
- [PASS] J2 **PRD-decision conformance** — decisions 2–8 honored verbatim (scan scope, status policy, degree of similarity, partial-split remainder, Source comma-list, transition multi-line, bundle category=max). Decision 1 (placement) has a minor structural divergence — see advisory A1.
- [PASS] J3 **Edge / error paths** — no `[slug]` line found → warning + skip + exit 0 (unchanged); line under no project section → falls back to declared project; two bundle lines in same project/section → handled in order (verified); missing target project section → warning + continue. Empty `###` headers left behind after moves are pre-existing documented behaviour.
- [PASS] J4 **Ponytail over-engineering pass (ultra)** — see advisory A2; net near-lean, no blocking complexity.
- [PASS] J5 **UAT gaps** — see UAT hand-off list.

## Findings

### Blocking (→ REQUEST_CHANGES)
None.

### Advisory (consider / over-engineering)
- **A1** — `.agents/skills/product-layer/SKILL.md`: PRD decision 1 says the similarity check lives "in `### 1. Read the model`"; the implementer placed it as a sibling top-level section `### 2. Similarity check` (with the slug/categorise block moved to `### 3`). The required *ordering* (after pick-up, before slug/categorise) and the described flow are fully honored, so this is structural, not behavioural. The implementer's own report also inaccurately claims it is "inside `### 1. Read the model`". Consider renaming the narrative or the section to match; non-blocking.
- **A2** — `bin/transition-task.sh:L254-269`: `project_of()` rescans the full prefix for every slug line (O(n·m)), separate from the collection loop. A single pass tracking the current `## <project>` while collecting would be O(n) and drop the helper. Marginal for small task files; advisory `shrink` only.
- **A3** — `bin/test-transition-task.sh:394`: the PRD's literal multi-line command used `--dry-run`; the committed test runs a real transition (justified: temp workspace is not a git repo, so `--dry-run` would make assertions readable only via temp copies). I separately verified `--dry-run` works. Advisory wording mismatch only.

## Ponytail debt (harvested from changed files)
No ponytail: debt. Clean ledger. — `grep -rnE '(#|//) ?ponytail:'` over the changed files (and repo) returned no markers.

## UAT hand-off list
1. **Skill flow walkthrough** (PRD Testing 3): next real product-layer session — pick a task with a known similar task; verify candidate proposal with one-line "why", the full/partial/none degree-of-similarity conversation, and (on full acceptance) one `[slug]` across all chosen lines, a multi-source task file, and one PRD.
2. **First real multi-line transition** (PRD Further notes): langfuse task `langfuse-agentic-operations` is `in-prd` with 3 annotated lines, never transitioned. Its first transition (to `prd-ready`) exercises the fix for real — confirm all 3 lines move (1 under `## all`, 2 under `## langfuse`).
3. **CONTEXT.md glossary**: PRD suggested adding "merge bundle" and "degree of similarity" to `CONTEXT.md`; the implementer added them to the skill's `## Glossary` (SKILL.md:228-233) because CONTEXT.md is outside the worktree. If CONTEXT.md is expected to carry shared vocabulary, copy the two terms there.
4. **Placement wording (A1)**: reviewer to decide whether the "inside `### 1. Read the model`" wording in the PRD/decision should be reconciled with the actual `### 2. Similarity check` section heading — cosmetic.
