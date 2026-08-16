## Decision: Single-line relocation project for multi-line bundles

**Status**: accepted
**Date**: 2026-08-16
**Task**: task-pickup-similarity-merge
**Session**: b77c5e2b-a870-40c7-bcad-effcbc45332a

### Context

`bin/transition-task.sh` moves task lines in `docs/tasks.txt` between status
sections. Historically it located the (first) line containing `[slug]` and
moved it into the project section declared by the task file's `**Project**`
field. The PRD requires that a merged bundle's transition move **all** lines
annotated with `[slug]`, each into **its own** project section (lines under
`## all` stay under `## all`), while keeping single-line behaviour unchanged.

### Problem

For a multi-line bundle spanning projects, the destination project is not
unambiguous: the task file declares one project, but each task line lives under
its own `## <project>` section. Using the declared project for every line would
incorrectly relocate all lines into one section. Yet blindly using each line's
own section would change behaviour for single-line tasks whose line happens to
sit in a different project than the task file's declared `Project`.

### Alternatives

- Use the task file's declared project for every line (old behaviour) — fails
  the "lines stay in their own project" requirement for bundles.
- Use each line's own enclosing project for every line, always — changes
  single-line behaviour when a line's section differs from the task file's
  declared project.

### Decision

When collecting `[slug]` lines: if there is exactly **one** line, relocate it
into the task file's declared project (legacy behaviour, unchanged). If there
are **multiple** lines (a bundle), relocate each line into the project section
it currently lives in (`## all` stays under `## all`), falling back to the
declared project only if a line is not under any project section.

### Rationale

Preserves the deterministic contract of single-line transitions while
satisfying the bundle requirement that every line closes in its own project.
Minimal, targeted change to the existing Python block.

### Consequences

- Single-line transitions behave exactly as before (regression tests pass).
- Multi-line bundles close all their lines, each under its own project.
- `docs/tasks.txt` may retain empty `### <status>` headers where lines were
  removed (the script never deletes empty status sections — pre-existing
  behaviour, unchanged).

### Revision triggers

- If `docs/tasks.txt` starts allowing a `[slug]` line outside any `## <project>`
  section for a bundle (currently falls back to the declared project).
- If single-line tasks are ever expected to follow the line's own section
  instead of the task file's declared project.
