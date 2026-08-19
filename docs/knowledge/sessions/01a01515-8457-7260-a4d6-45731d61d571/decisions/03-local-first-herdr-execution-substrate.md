## Decision: Local-first herdr execution substrate (validated operating model)

**Status**: accepted
**Date**: 2026-08-19 04:20
**Task**: multi-repo-delivery-bookkeeping-prs
**Project**: software-factory
**Session**: sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl
**Summary**: Local-first execution substrate via herdr: dedicated worktree branch + pane, host owns git, sandbox container is containment, GitHub is repo/PR/evidence layer; --continue respawn continuity works; timeout cap 7200s.

### Context

The GitHub Actions assembly-line loop kept failing Large tasks: a `timeout_sec` of 1800 × `respawn_cap` 3 killed the implementer three times at 30-min intervals, the runner worked on an ephemeral worktree so code was lost, evidence pushes exceeded GitHub's 100MB cap, and the run was a 90-minute blind black box (no mid-run logs, no host visibility).

### Problem

How to deliver factory tasks with full observability and durable state, without sacrificing the no-direct-push rule (the host driver owns git; the agent never runs git).

### Alternatives

- **GitHub Actions (status quo)** — rejected: blind, ephemeral, timeout/evidence-capped; the harness loses even when the agent wins.
- **opensource/woodpecker** — deferred unattended option; doesn't fix the inner bugs (they live in `bin/` + `config/implementer.json`, not the CI runner).
- **Local herdr run (chosen)** — a herdr worktree (branch `factory/local-run/<slug>-<uuid>`), the sandbox container as containment, the host driver owning git, GitHub as the repo/PR/evidence layer.

### Decision

Execute the factory run locally: `herdr worktree create` a dedicated branch/pane, run `bin/factory-run.sh --headless` through the **driver on the host** with the agent in the sandbox container. Raise all PRs from the local run; never push master directly.

### Rationale

Full host-side observability (every `tool_execution_start`, `message_end`, report is inspectable); the worktree edits are durable on disk across respawns; container + read-only `/workspace` mount keeps the agent sandboxed; the no-direct-push rule is preserved (agent commits nothing — the host authors the single commit at delivery).

### Consequences

- **Respawn continuity works**: on kill, a fresh container `--continue`s the same pi session (`--session-dir` seeded from the prior attempt); edits survive on disk.
- **Timeout must cover the full task**: hard cap 3600s still killed attempt 1 of this run during final verification. Large tasks need 7200s (or mid-run checkpointing/evidence rotation).
- Evidence still balloons locally (see decision 05) — harmless on disk but storage-relevant.
- This run is the proof-of-record: implementer (2 attempts + respawn) → PR → adversarial review → revision → APPROVE → UAT-merge, all observable.

### Revision triggers

- An unattended CI runner that is fully observable and survives Large tasks without timeout kills.
- If `--continue` session continuity is ever shown to lose context across respawns.
