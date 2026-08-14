---
name: review-ops
description: Run contract for the autonomous code-reviewer agent. Defines the exact review protocol inside the sandbox — orient on the PR/PRD, diff base...head read-only, run the PRD verification commands, run the deterministic and judgment check classes (including the Ponytail over-engineering pass), and assemble the fixed-schema outbox report with a verdict. Add a robustness check here (a skill edit), never in the host driver.
---

# Review Ops — Review Worker Run Contract

This is the operational contract for the **code-reviewer** agent running headless
inside the sandbox container. The host driver (`bin/review-run.sh`) owns all git
mutations, `gh` calls, PR comment, labels, and lifecycle transitions. You own the
review itself in the worktree + the outbox report. Follow this contract exactly.

## 0. Read your brief first

Read `/sandbox/brief.md` before anything else. It carries the PR URL, PRD path
(read-only in `/workspace`), task slug, review-session UUID, worktree/api paths,
the **base + head refs** for your diff, the PRD verification commands, the outbox
paths, and the binding rules. The brief is authoritative for this run.

## 1. Orient

- The PRD: read it fully from the read-only `/workspace` mount. Extract the user
  stories, the file-tree diff (scope), the implementation decisions, the out-of-scope
  list, and the **Testing decisions / verification commands**.
- The checkout: the PR head is checked out at `/sandbox/worktree` (read-only for
  you — never write). The base ref is fetched so you can diff.
- The brief: note the exact `base...head` refs to diff (e.g. `origin/<base>...HEAD`
  or the recorded SHA pair).

## 2. Diff `base...head` (read-only git)

You may run read-only git only:

```
git -C /sandbox/worktree status            # sanity: clean-ish, on the PR head
git -C /sandbox/worktree diff <base>...<head>   # the full PR diff
git -C /sandbox/worktree diff --stat <base>...<head>
git -C /sandbox/worktree log <base>..<head>     # what the PR adds
```

Never mutate git state, never `gh`.

Build a precise map: stop on EVERY user story and EVERY file in the PRD's file-tree
diff; record which diff hunks / files provide evidence for each.

## 3. Run the PRD verification commands

The brief lists the PRD's acceptance commands. Run them inside the worktree as the
PRD specifies (e.g. `bash bin/test-*.sh`, `pytest`, `npm test`). Worktree deps may
already be present or rebuildable; if a command needs a secret, a remote, or a host-only
tool you don't have, **record it as deferred with the exact reason**, never skip the
record. For each command record: command, exit status, key output, and whether it is
a real run or a deferred run.

## 4. Deterministic checks (mechanical — PASS/FAIL with evidence)

Run the fixed set below. Each is a discrete PASS/FAIL with concrete evidence.

- **D1 — PR metadata sane**: title/branch parse to a well-formed factory PR
  (`[factory] <slug>: …` and/or branch `factory/<slug>/<ts>`); base/head refs exist;
  diff is non-empty and scoped.
- **D2 — Worktree clean / read-only**: `git status` shows the PR head checked out;
  the reviewer made no changes (guardrail: clean worktree before finishing).
- **D3 — Scope containment**: every changed file/dir in `base...head` is within the
  PRD's file-tree diff (no out-of-scope edits, no stray deps, no unrelated
  refactors). Unknown/extra in-diff files are findings.
- **D4 — Scope ⊆ PRD file-map**: every file the PRD's file-tree diff claims is
  actually present in the diff (nothing promised is missing).
- **D5 — Story → diff coverage**: every user story maps to at least one diff hunk /
  file that implements it (no unimplemented story). Conversely, the diff has no
  capability that no story asks for.
- **D6 — No secrets / stray deps**: scan the diff for committed credentials, keys,
  `.env` with real values, and for new dependencies (gems/requirements/package) added
  without PRD justification.
- **D7 — Implementer report matches actual diff**: compare the implementer's archived
  report (`docs/implementations/<date>-<slug>/report.md`) against the actual diff —
  claimed stories/files present, nothing silently dropped, verification claims
  plausible.

## 5. Judgment checks (reasoning — PASS/FAIL with rationale)

- **J1 — Story intent**: does each story's *intent* (not just literal wording) hold
  — would the observable behavior described actually work from the diff?
- **J2 — PRD-decision conformance**: do the implementation decisions and any
  referenced design decisions appear honored (e.g. archive location, read-only
  guarantees, config shape)? Flag divergences.
- **J3 — Edge / error paths**: are error/edge cases in the changed code handled
  (empty input, missing files, non-zero exits, missing config)? Missing handling is
  a finding.
- **J4 — Ponytail over-engineering pass** (advisory subclass, never alone blocking):
  run `ponytail-review` over the `base...head` diff at `ultra` mode — report findings
  in the `L<line>: <tag> <what>. <replacement>.` format with tags
  `delete/stdlib/native/yagni/shrink`. Then run `ponytail-debt` to harvest existing
  `ponytail:` shortcut markers in changed files into the report's UAT section.
  Complexity findings are **advisory**; they may not alone flip the verdict to
  REQUEST_CHANGES.
- **J5 — UAT gaps**: precise list of what the user must still inspect/approve before
  this PR is truly done (anything not verifiable in the sandbox, any judgment call).

## 6. Assemble the outbox report (fixed schema)

Write `/sandbox/outbox/report.md` to this fixed schema so consumers never break:

```
# Code Review
- Reviewed: <PR url> (repo: <repo>, PR #<num>)
- Task: <slug> · PRD: <path> · Review session: <uuid>
- Base: <sha|ref> → Head: <sha|ref>

## Verdict
APPROVE | REQUEST_CHANGES — <one line reason>

## Verification results
- Per PRD verification command: ran / deferred + exit + evidence.

## Story-by-story
- [PASS|FAIL] US<N> <story> — evidence (diff/file/line).

## Deterministic checks
- [PASS|FAIL] D<n> <name> — evidence.

## Judgment checks
- [PASS|FAIL] J<n> <name> — reasoning.

## Findings
### Blocking (→ REQUEST_CHANGES)
- <file>:<detail> — why it blocks (correctness, scope breach, decision violation).
### Advisory (consider / over-engineering)
- <file>:<ponytail finding L<line>: <tag> ...> — complexity/UX, never alone blocking.

## Ponytail debt (harvested from changed files)
- <file>:<line>, <what>. ceiling: <...>, upgrade: <...>. (or "No ponytail: debt.")

## UAT hand-off list
- <precise items the user must inspect/approve>
```

## 7. Finish

Exit 0 on a complete report; exit 1 if you must hand back a partial report. Either
way `report.md` is written. The driver reads the outbox, archives it, posts it to the
PR, updates the label, and (on APPROVE) transitions the task `in-progress → in-review`.
You never do any of that.
