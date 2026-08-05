## Decision: Capture server uses fixed defaults, no config surface

**Status**: accepted
**Date**: 2026-08-04 12:22
**Task**: x-capture-instrument
**Project**: feed-analyser
**Session**: sessions/019fc8f4-ad2b-7aea-ac8b-df06363d0aba/session.jsonl

### Context

The earlier vision called for a "configurable data directory" and a "configurable server port". For
a minimal dumb-receiver server these add configuration surface with no benefit at v1 scale.

### Problem

Configuration files, CLI flags, and data-directory abstraction are exactly the over-engineering the
capture instrument is meant to avoid. The defaults need to be fixed and boring so the
implementation agent and the user have no knobs to reason about.

### Alternatives

- **Configurable data directory + port (config file / CLI flags)** — Rejected. Config surface is
  speculative; the user runs one server in one place.
- **Data in a separate configurable location** — Rejected; fixed path beside the server is simpler.

### Decision

- **Data file**: a single `artefacts.jsonl` beside the server (`server/artefacts.jsonl`), opened in
  append mode, write + flush per line. Gitignored.
- **Port**: fixed default `8765`.
- Each of the two may be overridden by **at most one env var** (e.g. `CAPTURE_PORT`, and by
  implication a data-path override if ever needed) — no config file, no CLI flags.
- Extension hardcodes the same default; changing the port means changing two constants.

### Rationale

- Removes configuration ceremony entirely for the common case.
- One obvious place to find the data (`server/artefacts.jsonl`) and one obvious port.

### Consequences

- FRESH simplicity: no config parsing, no directory setup, fewer failure modes.
- If the user later runs the server from elsewhere, a single env var covers it without new
  infrastructure.

### Revision triggers

- If the server is ever run in more than one location or port concurrently.
- If a real need emerges for per-run data isolation beyond one dev box.
