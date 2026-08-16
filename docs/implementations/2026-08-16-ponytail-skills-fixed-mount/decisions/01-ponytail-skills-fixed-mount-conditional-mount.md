## Decision: Skills `/skills` bind mount is conditional on host-skills presence

**Status**: accepted
**Date**: 2026-08-16
**Task**: ponytail-skills-fixed-mount
**Project**: software-factory
**Session**: 0ded66e7-a908-4838-ace5-03de80e8fc0d

### Context

The PRD file map says `run_container()` adds `-v "$HOST_SKILLS:/skills:ro"` beside the
existing workspace mount, and US4 says absent host skills → run proceeds WITHOUT the
`--skill` flags (warn-and-run: never fail-fast, never silent). Binding a `-v` mount whose
source path does not exist makes the container runtime refuse to start — which would block
the run, contradicting US4's "never blocks a run" requirement.

### Decision

The `/skills` bind mount is added **only when** `$HOST_SKILLS` is a directory that exists
at run time. When absent, the driver logs the loud warning
(`ponytail skills not found at <path>; running without ponytail discipline`) and passes
neither the `--skill` flags nor the mount. The `--skill` flags themselves still resolve to
`/skills/<name>` whenever the mount is present.

Implementation: a `local skills_mount=()` array; `skills_mount=(-v "$HOST_SKILLS:/skills:ro")`
only in the present branch, then `"${skills_mount[@]}"` is spliced into the podman invocation
beside the workspace mount.

### Rationale

Keeps both PRD invariants intact: US4's warn-and-run (a missing checkout must never fail a
run) and the fixed `/skills` delivery path (when the checkout exists, the container sees the
same files at `/skills`, no copy, no image rebuild). Making the mount unconditional would
re-introduce exactly the fail-fast the decision 01 explicitly rejected.

### Consequences

- When host skills are present: mount + six `--skill /skills/<name>` flags, as specified.
- When host skills are absent: clean warning, no flags, no bad mount → run proceeds.
- The mock-podman smoke tests exercise the present branch (stub host-skills dir in the
  fixture scratch); the US4 branch is asserted structurally (warning string present in the
  driver + `-d "$HOST_SKILLS"` guard).

### Revision triggers

- If a future runtime can tolerate a `-v` mount with a missing source (auto-create), the
  conditional could be relaxed to always mount. No change required today.
