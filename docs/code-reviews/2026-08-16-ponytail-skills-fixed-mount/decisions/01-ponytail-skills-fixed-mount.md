# Decision 01 — ponytail-skills-fixed-mount: conditional `/skills` mount reconciling US2/US4

- **Session**: 0bb584c8-f18c-4655-97b9-bc100c39a087 (reviewer)
- **Date**: 2026-08-16

## Context

US2 requires the `/skills` mount + `--skill /skills/<name>` flags; US4 requires a loud
warn-and-run when the host skills checkout is absent. A naive implementation that always
emits `-v "$HOST_SKILLS:/skills:ro"` would pass a non-existent mount source to podman when
the host checkout is missing, breaking US4's "never block, never fail".

## Decision

The `/skills` mount and the `--skill` flags are **conditional on `[ -d "$HOST_SKILLS" ]`**.
When the dir exists: mount `-v "$HOST_SKILLS:/skills:ro"` + all six flags. When absent:
skip both, emit `WARN: ponytail skills not found at <path>; running without ponytail
discipline` to stderr, and run. This is consistent with the implementer's decision 01
(`docs/implementations/2026-08-16-ponytail-skills-fixed-mount/decisions/01-...-conditional-mount.md`).

## Review outcome

Correct and consistent with the PRD's US2+US4 intent. Verified the empty `skills_mount=()`
array expands safely under `set -euo pipefail` (`set -u`) on bash 4.4+ (bash 5.2 in container),
so the no-mount path cannot error. Non-blocking advisory: the unused `${WORKSPACE}` braced-form
expansion line in both drivers is dead flexibility (config only uses unbraced `$WORKSPACE`).
