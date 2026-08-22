## Decision: Capture v1 is text-only; keep the vision a product document

**Status**: accepted
**Date**: 2026-08-04 12:22
**Task**: [x-capture-instrument](../../../../tasks/x-capture-instrument.md)
**Project**: feed-analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Various product documents (vision) carry no engineering jargon; the VISION.md is rewritten as a user-perspective, implementation-free document (why it exists → what it is

### Context

The X Capture PRD (2026-07-25) was created under the old single-phase product layer. The vision
document written alongside it drifted from its purpose — it described implementation details
(JSONL, blob store, configurable data directory, MV3, side panel, a generic id/type/source
artefact envelope) rather than the product from a user's perspective. This leaked a speculative
blob store and image/screenshot capture into the product's framing, even though the PRD scoped
them out.

### Problem

The vision document confused engineers and the implementation model. It promised generic content
capture (arbitrary artefact types, image/screenshot blobs, configurable infrastructure) while the
PRD described a specific, minimal X-tweet saver. A product vision should capture the essence from
a user's perspective with no technical jargon; technical/evolving design belongs in the PRD /
technical docs, which are out of scope for now.

### Alternatives

- **Delete the vision document entirely** — Considered, then rejected. The vision has legitimate
  long-horizon value (where the product evolves, e.g. captured content eventually becoming a base
  for search/enrichment/data pipelines). A vision should state that at a product level without
  naming storage mechanisms.
- **Keep the vision as-is** — Rejected. It was confusing the context with implementation detail.
- **Implement images/screenshots + blob store in v1** — Rejected. Contradicts the "thin, dumb
  receiver" intent; binary handling is exactly the speculative scope this project avoids.

### Decision

- Various **product documents (vision) carry no engineering jargon**; the VISION.md is rewritten as
  a user-perspective, implementation-free document (why it exists → what it is → what it's not →
  where it's headed). References to it (PRD header, factory-context) are kept valid.
- **v1 scope is text-only**: tweet URL, author, tweet text, links, selected text, notes. Images,
  screenshots, and binary/blob storage are explicitly deferred and out of scope.
- Texture for any of the PRD concerns if the user wants later decisions around them.

### Rationale

- A vision that reads as a product story (user's words) stays stable and useful, whereas one full
  of implementation detail goes stale or misleads.
- Shipping text-only first gets a working capture loop quickly and iterates (the user's stated
  preference: get something working, then iterate — not an overengineered, unextensible mess).

### Consequences

- The vision doc is now the single home for product intent; the PRD is the home for implementation.
- No blob store, no image handling, no configurable data directory in v1 — smaller file tree and
  simpler server.
- Future capture modalities (images, screenshots, audio, full-page) are product-evolution scope,
  to be added when real use proves them.

### Revision triggers

- If the user begins capturing images/screenshots in practice, the text-only scope and the vision's
  "What This Is" should be revisited together.
- If the vision drifts back toward implementation detail in a later edit.
