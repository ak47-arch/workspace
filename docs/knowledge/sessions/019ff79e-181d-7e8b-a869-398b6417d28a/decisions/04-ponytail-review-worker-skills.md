## Decision: Ponytail wired as review-worker skills via `--skill` flags — not the interactive pi-extension or MCP

**Status**: accepted
**Date**: 2026-08-14 00:30
**Task**: code-review-agent
**Project**: software-factory
**Session**: sessions/019ff79e-181d-7e8b-a869-398b6417d28a/session.jsonl

### Context

The code-review-agent PRD was gated READY. The user then asked to wire "the entire
ponytail infrastructure" (`opensource/ponytail` — lazy-senior-dev / over-engineering
review) into the review agent, replacing the untracked side-requirement that had
previously only embedded ponytail *as prose* in the implementer persona.
`opensource/ponytail` ships: six pi-format skills (`skills/ponytail*`), a native pi
extension (`pi-extension/` — status bar, `/ponytail` mode commands, mode
persistence), an MCP server (`ponytail-mcp/` — ruleset via prompt/tool for
MCP-only hosts), hooks, commands, and plugin manifests for ~20 other harnesses.

### Problem

What does "the entire infrastructure" mean for a **headless** review worker
(`pi --mode json -p` in the sandbox container), and how do we scope it to the
reviewer **without** polluting the shared `.pi/settings.json` (currently only
`langfuse-tracing`) or leaking ponytail skills into the implementer and interactive
sessions?

### Alternatives

- **Copy/symlink skills into `.agents/skills/`** — pollutes every agent (implementer
  included) and duplicates content that `workspace-portability` already updates.
  Rejected.
- **Add `"skills": [...]` to the shared `.pi/settings.json`** — global for the whole
  workspace. Rejected for the same reason.
- **Load the interactive `pi-extension` in the headless worker** — it injects rules
  with mode filtering, but its surface is a status bar + slash commands that do not
  exist under `pi --mode json -p`; UI risk with no review value. Rejected for the
  worker (stays available for interactive use via `opensource/`).
- **Wire `ponytail-mcp`** — exists for hosts whose only injection point is a prompt
  menu/tool; pi injects skills natively, so MCP is redundant. Deferred.

### Decision

`review-run.sh` mounts the workspaces read-only and passes **repeatable pi CLI
`--skill` flags** (only in the review invocation) pointing at
`/workspace/opensource/ponytail/skills/{ponytail,ponytail-review,ponytail-audit,ponytail-debt,ponytail-gain,ponytail-help}`.
`PONYTAIL_DEFAULT_MODE=ultra` is added to the reviewer's env allowlist. The
`review-ops` run contract gains a **Ponytail over-engineering pass**: `ponytail-review`
over `base...head` reported as an **advisory subclass** (never alone blocking), plus
a `ponytail-debt` harvest of existing `ponytail:` shortcut markers in changed files.
The interactive pi-extension and MCP server are **out of scope** for the worker.

### Rationale

Reviewer-scoped by construction: the flags exist only in `review-run.sh`, so the
shared settings file, the implementer, and interactive sessions are untouched. Zero
vendoring: skills load live from the read-only `opensource/` checkout, so updates
flow through the existing workspace-portability opensource update mechanism. Skills
are pi's native injection point — the same mechanism that loads `review-ops`.

### Consequences

- The reviewer gets all six ponytail skills; findings land in the report as
  advisory (complexity/style), keeping correctness blockers authoritative.
- The implementer's ponytail stays prose-only until a separate task upgrades it
  via the same `--skill` mechanism.
- `config/reviewer.json` gains a small `ponytail` node (`skills_dir`,
  `default_mode`); the driver test suite asserts the flags in the podman invocation.
- The PRD is amended (story for the ponytail pass, testing seams) and re-gated.

### Revision triggers

- A reviewer-specific interactive need appears (status bar/commands) in the worker.
- A non-pi host needs the same ruleset → revisit `ponytail-mcp`.
- The implementer ponytail-upgrade task merges and needs flag sharing across drivers.