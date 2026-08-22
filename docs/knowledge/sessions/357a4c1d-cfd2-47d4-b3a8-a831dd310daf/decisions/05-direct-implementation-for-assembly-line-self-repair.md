## Decision: Direct implementation for assembly-line self-repair

**Status**: accepted
**Date**: 2026-08-17 02:12
**Task**: [sandbox-credential-mounting](../../../../tasks/sandbox-credential-mounting.md)
**Project**: software-factory
**Session**: [session.jsonl](../session.jsonl)
**Summary**: When a task's deliverable is required for the implementer itself to run (credential mounting, driver bugs, sandbox plumbing), the product-layer session implements it dire

### Context

The factory's assembly line is staffed by the implementer agent: the product layer produces a Final PRD, the implementer picks it up in a sandbox and raises a PR. While implementing `task-pickup-similarity-merge`, every implementer run failed at container boot because the driver could not supply LLM credentials (the key lives in pi's `auth.json`, not the host env — see decision 04). Fixing that credential path is itself a software-factory task — but the implementer cannot run any task until the fix lands.

### Problem

A task whose deliverable is a repair to the assembly line itself (the implementer/reviewer drivers, sandbox image, or credential plumbing) cannot be implemented by the normal pipeline: the pipeline is broken until the fix ships. Following the letter of the Small-task flow (product layer → PRD → implementer) would deadlock.

### Alternatives

- **Block on the broken pipeline** — rejected: no path forward until someone fixes the drivers manually.
- **Write the PRD and wait for a manual host fix** — accepted in part: the PRD was still written and archived for traceability, but the fix itself was not deferred.
- **Direct implementation in the product-layer session** — accepted: the product layer implemented the fix in-session, ran the full driver test suites (60 + 63 tests), committed, and transitioned the task to complete. The PRD documents the exception explicitly ("bootstrapping exception").

### Decision

When a task's deliverable is required for the implementer itself to run (credential mounting, driver bugs, sandbox plumbing), the product-layer session implements it **directly** — mirroring the Trivial-task path — rather than delegating to a pipeline that cannot boot. The PRD is still written, the decisions are still captured, and the task still transitions through the normal lifecycle (in-prd → prd-ready → … → complete) for traceability. The exception is recorded in the PRD so downstream readers know why no implementer session exists.

### Rationale

The deadlock is real: the implementer's first action is reading the PRD inside a container that refuses to boot without the exact credential path the task fixes. Direct implementation is the only non-blocking path, and this class of task is small and low-risk (driver shell changes with existing test suites to verify). Keeping the PRD + decisions preserves the factory's traceability contract.

### Consequences

- `sandbox-credential-mounting` was implemented and completed without an implementer run — the first task of this kind.
- The driver test suites gained the new auth.json fallback tests, so the normal pipeline now verifies this change on every future run.
- Future self-repair tasks can follow this precedent: PRD + direct implementation + full test suite + lifecycle transition.
- Risk: product-layer sessions doing implementation work blurs the layer boundary — acceptable only for pipeline-blocking fixes, never for normal feature work.

### Revision triggers

- If the implementer gains a self-healing mode (e.g. a rescue/repair image that boots without LLM credentials), the exception can be retired.
- If a self-repair task exceeds the Small category (crosses many modules, no existing tests), re-evaluate — direct implementation without the pipeline's discipline becomes riskier.
