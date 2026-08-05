## Decision: Capture API contract — one POST endpoint, flat artefact

**Status**: accepted
**Date**: 2026-08-04 12:22
**Task**: x-capture-instrument
**Project**: feed-analyser
**Session**: sessions/019fc8f4-ad2b-7aea-ac8b-df06363d0aba/session.jsonl

### Context

The System Architecture phase for the X Capture instrument needed a concrete endpoint contract and
data-model shape. The earlier vision sketched a generic artefact envelope (`id`, `type`, `content`,
`source`, `timestamp`, `metadata`) and an alternate endpoint (`POST /api/artefacts`).

### Problem

The server is a "dumb receiver" — it should append a capture and do nothing else. A generic
envelope or multiple endpoints would add surface area and confuse the implementation agent without
adding value. The contract needed to be minimal and unambiguous.

### Alternatives

- **`POST /api/artefacts` with a generic envelope (`id`, `type`, ...)** — Rejected. The generic
  envelope is speculative; a flat record can grow fields later without breaking existing lines.
- **Multiple routes (POST + GET + list + resource id)** — Rejected. The dumb receiver only
  appends; no read surface in v1.
- **Client-stamped timestamp** — Rejected in favour of server-stamped `captured_at` for an accurate
  save-time (the client clock may be wrong).

### Decision

- **Endpoint**: `POST /api/capture` (matches the product's language — "you capture something").
  No other routes.
- **Request body**: flat artefact JSON; no `id`, no `type`, no metadata envelope.
- **Response**: `200` + `{ "status": "saved", "captured_at": "..." }`.
- **`captured_at`** is stamped by the **server** on receipt.
- **No dedup / uniqueness** — each capture appends independently; downstream handles merging.

### Rationale

- Matches the minimal product model (capture ends at the JSONL file).
- A flat record can grow one field at a time without versioning — cheap to evolve.
- One endpoint keeps the server and the extension's contract simple and testable.

### Consequences

- Extension and server share only this one JSON contract.
- No list/read API in v1; any read surface comes later with backend consumption.
- Tests target exactly one handler.

### Revision triggers

- If a read/list/query surface becomes a real need before backend analytics exists.
- If a single capture must reference or supersede an earlier one (introducing ids/edits).
