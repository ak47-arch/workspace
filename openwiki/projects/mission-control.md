---
type: Project
title: Mission Control
description: Read-only Rust daemon for monitoring coding-agent sessions — collects signals from herdr and pi, applies rules, and surfaces a birds-eye view via TUI and web dashboards.
tags: [rust, monitoring, herdr, tui, session-management]
resource: /mission-control
---

# Mission Control

A read-only birds-eye view over your collection of running coding-agent panes. It knows what every agent is doing, where each conversation is, which panes are blocked, and which panes are waiting on you.

## Architecture

```
herdr JSON-RPC ──┐
pi .jsonl tail ──┤── Collectors ──→ Reducer ──→ State Store ──→ Event Emitter
cwd scan ────────┘                                              │
                                                    ┌───────────┼───────────┐
                                                    ▼           ▼           ▼
                                                 TUI        Web UI    Push clients
```

**Key design rules:**
- Collectors emit `RawSignals` types only — they never import herdr's schema or pi's jsonl layout
- Backend has zero mutating capability — no pane manipulation
- Clients never touch sources — they consume `PaneView` events only

## Workspace Structure

```
mission-control/
├── Cargo.toml                    # Workspace root
├── mc-schema/                    # Phase 0: types, serde, schemars
│   └── src/
│       ├── raw_signals.rs        # HerdrPaneSnapshot, PiSignals, ProjectProfile
│       ├── pane_view.rs          # PaneView, Flags, Attention, Vitals
│       ├── project.rs            # ProjectView, ProjectKind, ArtifactHint
│       └── events.rs             # EventKind, EventEnvelope, PaneViewPatch
├── mc-core/                      # Phase 1-2: library
│   └── src/
│       ├── collector/
│       │   ├── herdr.rs          # JSON-RPC poll to herdr
│       │   ├── pi.rs             # inotify tail of .jsonl files
│       │   └── project.rs        # notify on cwd mtime
│       ├── reducer.rs            # pure fn: signals → Vec<PaneView>
│       ├── state.rs              # Arc<Mutex<ring + seq>> state store
│       ├── rules.rs              # Flag computation + config thresholds
│       └── transport/
│           └── unix_socket.rs    # JSON-RPC over Unix socket
└── mc/                           # CLI binary
    └── src/
        ├── main.rs               # CLI: mc status | mc serve | mc tui | mc web | mc diagnose
        ├── status.rs             # Inline collectors + reducer, prints table
        ├── daemon.rs             # Long-running daemon
        └── tui.rs                # ratatui client
```

## Data Sources

1. **herdr** — Terminal workspace manager. Mission Control reads `HERDR_SOCKET_PATH` (set in every herdr-managed pane) to discover pane state via JSON-RPC.
2. **pi** — The coding agent. Mission Control tails `.jsonl` files via inotify to track agent activity.
3. **cwd scan** — Filesystem notifications on project directories for workspace context.

## Subcommands

| Command | Description |
|---------|-------------|
| `mc status` | Print the "needs-you" lane — all panes sorted by attention |
| `mc serve` | Start the long-running daemon |
| `mc tui` | Launch the ratatui dashboard |
| `mc web` | Start web dashboard (HTTP + SSE, default :9876) |
| `mc diagnose` | Session mapping analysis |

## Rules (Flag Computation)

Rules are config-driven threshold checks that determine pane state:

| Rule | Default | Effect |
|------|---------|--------|
| `runaway_threshold` | 25 | `tools_since_last_user >= this` → runaway flag |
| `idle_threshold_secs` | 900 | `last_activity` older than this → idle_long flag |
| `arc_turns` | 5 | Last N user turns in conversation arc |

Config file: `~/.config/mc/config.toml` (optional, all fields have defaults)

## How It Works

1. **Collectors** poll/observe their data sources and emit `RawSignals`
2. **Reducer** applies pure-function signal merge to produce `PaneView` instances
3. **State Store** holds an `Arc<Mutex<ring + seq>>` mirroring herdr's EventHub structure
4. **Event Emitter** sends `EventEnvelope` instances to connected clients
5. **Clients** (TUI or Web UI) subscribe to events and render the current state

## Source Files

| File | Purpose |
|------|---------|
| `/mission-control/Cargo.toml` | Rust workspace manifest |
| `/mission-control/mc-schema/src/lib.rs` | Schema types entrypoint |
| `/mission-control/mc-core/src/collector/herdr.rs` | herdr JSON-RPC collector |
| `/mission-control/mc-core/src/collector/pi.rs` | pi .jsonl tail collector |
| `/mission-control/mc-core/src/reducer.rs` | Signal → PaneView reducer |
| `/mission-control/mc-core/src/rules.rs` | Flag computation engine |
| `/mission-control/mc/src/main.rs` | CLI entrypoint |
| `/mission-control/mc/src/status.rs` | One-shot status command |
| `/mission-control/mc/src/daemon.rs` | Long-running daemon |
| `/mission-control/mc/src/tui.rs` | ratatui dashboard |
| `/mission-control/DESIGN.md` | Full architecture decisions |
| `/mission-control/MISSION_CONTROL_PRD.md` | Product requirements document |
