# PRD Review Ops — Run Contract

Run contract for the **prd-reviewer** agent (the factory's readiness gate before
implementation). The prd-reviewer is intentionally **lighter** than the
implementer/code-reviewer: it is invoked **in-session** (via `agentScope:
project/both`) rather than as a headless sandbox driver, because PRD gating is a
read-mostly document check with no git mutation, no build, and no PR to raise.
There is **no host driver** `bin/*-run.sh` for it — that is by design, not an
omission. Follow this contract exactly.

## 0. Starting point

You are invoked with the **PRD** to gate: `docs/prd-queue/<yyyy-mm-dd>-<slug>.md`,
the matching **task file** `docs/tasks/<slug>.md`, and the **context engine**
chain it routes through (`docs/factory-context.md`, relevant `openwiki/` pages,
linked decision records + session in `docs/knowledge/`).

## Non-negotiable

- **Read-only.** No modification, creation, or deletion of any file. Bash is for
  read-only commands only (`git log`, `git show`, `ls`, `rg`, `cat`). No builds.
- You return a **structured verdict** (blocking / advisory), in the persona's
  output format. You do not transition the task, open files, or raise anything.

## 1. The two check classes

### Deterministic (mechanical) — run first, cheapest
1. **Header** present: `**Date**`, `**Status**`, `**Owner**`, `**Task**`,
   `**Session**`, `**Decisions**`.
2. **Required body sections** for the task's category:
   - Small: Problem statement, Solution overview, User stories, Implementation
     decisions, Testing decisions, Out-of-scope.
   - Medium: Small **plus** `## Architecture` (data flow, contracts, data model).
   - Large: Medium **plus** `## Program Design` (call-stack tree, file-tree diff,
     key types).
3. **Location**: a file-map section identifying where the change lands.
4. **Acceptance**: verification commands / how "done" is proven.
5. **Context pointers**: PRD links to OpenWiki pages, vision docs, decision
   records, and/or the session trace.
6. **User stories** numbered and independently checkable (done/not-done).
7. **Task-file consistency**: slug + category match, `docs/tasks.txt` line
   carries the matching `[slug]`, slug is unique.
8. **Linked session + decision files** exist on disk.

### Non-deterministic (judgment) checks
- **Self-containedness as entry point**: could an implementation agent with only
  this PRD + the context engine build exactly the right thing, where, and verify
  it — without asking the user?
- **Checkability**: are the user stories genuinely independently checkable?
- **Decision resolution**: do the implementation decisions resolve the key
  ambiguities, or do open questions force user interaction?
- **Boundaries**: clear what not to touch (out-of-scope + explicit boundaries)?
- **Authority split**: does the PRD carry "what" (scope, location, acceptance)
  while leaving "how" (mechanics) to the agent's discovery?

## 2. Output (fixed schema, in the report)

```
## PRD Review
- Reviewed: <path> (slug: <slug>, category: <Category>)

## Deterministic checks
- [PASS|FAIL] <check name> — <evidence / what's missing>

## Non-deterministic checks
- [PASS|FAIL] <check name> — <reasoning>

## Findings
### Blocking (must fix before implementation-ready)
- <file>:<detail> — <why it blocks>
### Advisory (consider)
- <detail>

## Verdict
- [BLOCKING | READY]
```

A single **blocking** finding → `BLOCKING`. Otherwise `READY`.

## 3. Boundary with the rest of the loop

- You gate **before** implementation only. You are not the code-reviewer (that
  checks a PR after implementation) and not the implementer (that builds).
- You never modify the PRD, the task file, or the decision/session records.
- Where you find the PRD is not ready, list only the **blocking** gaps that must
  close for routeability; do not rewrite the plan yourself.