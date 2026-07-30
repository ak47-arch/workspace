## Decision: Herdr-Pi Session Repopulation Architecture

**Status**: accepted
**Date**: 2026-07-30
**Project**: headroom-pi
**Session**: sessions/019fb3a9-bf84-79db-b194-c580b76e4228/session.jsonl

### Context

The workspace uses pi (coding agent) inside herdr (terminal workspace manager) panes. Each pi pane has a session file (~/.pi/agent/sessions/...) that tracks the conversation. When the system restarts, all pi processes are killed. Without a mechanism to restore the session-to-pane mapping, each pane would start a fresh pi session, and the user would have to manually find and resume the correct session via `/resume` or `pi -r`.

There are two related problems:
1. **System restart** — herdr's layout survives via snapshot/restore, but pi session paths need to be persisted and re-associated with panes on restart.
2. **Detach/reattach cycles** — when a pane's agent is released and reattached (e.g., during tmux-like workflows), the extension reloads but may miss the `session_start` event, so the session path is never re-sent to herdr.

### Problem

Find a way to persistently associate pi session files with herdr panes across system restarts and agent reattach cycles, so that:
- After restart, each pane automatically launches pi with the correct session file
- Mission Control (`mc status`/`mc serve`) can discover session data even when herdr's session path is missing
- The system works without manual intervention

### Alternatives

1. **File-watching in mission control** — Have mission-control watch the pi session directory with inotify/FSEvents and try to match sessions to panes by cwd. Rejected: mission-control is a read-only dashboard; adding a notification mechanism is complexity without benefit. The orphaned-session fallback exists as a last resort.

2. **Store session paths in herdr's snapshot only** — Rely purely on herdr persisting whatever session path it happens to know at snapshot time. Rejected: without the extension reporting the session path, herdr's snapshot would always have `agent_session: null` because herdr has no independent way to peek into pi's session file.

3. **Let pi write session paths to a well-known file** — Have pi write its current session path to a shared file that herdr could read. Rejected: this duplicates the extension's reporting mechanism and introduces file-system race conditions.

4. **Current approach (adopted)** — Two-layer recovery: (a) pi extension reports session path to herdr at runtime, herdr persists it in the snapshot, and restores it on restart; (b) mission-control's orphaned-session fallback scans session directories by cwd as a last resort.

### Decision

The session repopulation uses a three-layer architecture:

**Layer 1 — Pi Extension (runtime bridge):**
The `herdr-agent-state.ts` extension (installed by herdr into `~/.pi/agent/extensions/`) runs inside pi and reports the current session path to herdr via JSON-RPC over Unix socket:
- `pane.report_agent_session` — called on `session_start` and `agent_start`
- `pane.report_agent` — every state report includes the session path via `withSessionRef()`
- 10-second heartbeat (v6, manually added) — re-reads `sessionManager.getSessionFile()` and re-reports, recovering from missed events

**Layer 2 — Herdr Snapshot/Restore (persistence):**
Herdr's Rust codebase stores the session ref in terminal state (`terminal.persisted_agent_session`), captures it into the session snapshot (`PaneAgentSessionSnapshot`), and on restart generates a resume plan: `pi --session <path>`:
- `src/agent_resume.rs` — session ref types, resume plan generation, deduplication
- `src/persist/snapshot.rs` — captures `agent_session` into the on-disk snapshot
- `src/persist/restore.rs` — on restart, reads snapshot and launches `pi --session <path>`
- `src/app/api/panes.rs` — JSON-RPC handlers for `pane.report_agent_session` and `pane.report_agent`
- `src/app/actions.rs` — event handlers that store session refs into terminal state
- `src/events.rs` — `AgentSessionReported`, `HookStateReported` event types
- `src/terminal/state.rs` — `set_agent_session_ref_for_session_start()`, `persisted_agent_session` field, full-lifecycle hook authority

**Layer 3 — Mission Control Orphaned Session Fallback (last resort):**
If both layers 1 and 2 fail, mission-control's herdr collector (`mc-core/src/collector/herdr.rs`) scans pi's session directories by cwd:
- `find_orphaned_session_path()` — derives pi's session directory slug from the pane's `cwd`, finds the newest `.jsonl`, verifies the header `cwd` field
- `find_orphaned_session_path_by_header()` — fallback that scans all session directories and matches by header `cwd`

### Rationale

- **Reliability through redundancy** — Three layers with increasing fallback guarantee that sessions are almost always associated correctly. The primary path (extension → herdr snapshot → restore) covers 99% of cases.
- **No herdr fork needed** — The herdr source is consumed upstream with zero local modifications. The only custom change is a heartbeat added to the installed extension, which is a minor runtime patch.
- **Minimal intrusion** — The extension is purely observational; it doesn't read or parse session files, doesn't control pi's behavior, and doesn't persist anything itself.
- **General framework** — Herdr's agent session infrastructure is agent-agnostic; it supports pi, Claude Code, Codex, Cursor, OpenCode, OMP, Devin, Qoder, and others through the same `agent_resume.rs` + snapshot/restore mechanism.

### Consequences

- **Upstream dependency** — The herdr Rust codebase is a critical dependency. If upstream changes the snapshot format, restore logic, or API schema, session repopulation could break. We need to stay current with upstream releases.
- **Heartbeat is a manual patch** — The 10-second heartbeat in the extension (v6) is not in upstream herdr (v5 is the latest in source). It will be lost if the pi integration is reinstalled. Should be contributed upstream.
- **Mission Control's fallback is fragile** — The orphaned session fallback relies on cwd matching and newest-file heuristics. If the user has multiple sessions in the same cwd, the wrong one could be picked. This is acceptable because it's a last-resort fallback.
- **No custom fork to maintain** — Currently, we have no local modifications to herdr's source code. The workspace tracks upstream herdr at `opensource/herdr/` with `origin` pointing to a fork (`ak47-arch/herdr`) and `upstream` pointing to the original author (`ogulcancelik/herdr`). Both are identical.

### Revision triggers

- Herdr changes its snapshot format or restore mechanism in a way that breaks session path persistence.
- The heartbeat is added upstream (check if future herdr releases include it; if so, reinstall the integration and remove the manual patch).
- Mission Control's orphaned session fallback is shown by `mc diagnose` to be picking incorrect sessions.
- New agents are added to the workspace that need similar session repopulation support (verify they're supported by herdr's agent_resume framework).
- The ".pi" config directory name changes (rebranded distributions use `CONFIG_DIR_NAME`).