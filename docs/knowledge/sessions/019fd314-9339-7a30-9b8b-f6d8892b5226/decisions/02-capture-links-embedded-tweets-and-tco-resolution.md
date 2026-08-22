## Decision: Capture links include embedded/quote tweets and resolve t.co shortlinks

**Status**: accepted
**Date**: 2026-08-06
**Task**: [x-capture-instrument](../../../../tasks/x-capture-instrument.md)
**Project**: feed-analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: External links: for t.co anchors, resolve the real destination from the anchor's display text; if the text is not a recognizable URL, fall back to the t.co href.

### Context

During implementation, two link-capture flaws surfaced:

1. **`t.co` shortlinks were being dropped.** X wraps every external link in a
   `t.co` shortlink (`href="https://t.co/abc123"` whose display text is the
   real URL, e.g. `github.com/owner/repo`). The original scraper skipped any
   `https://t.co/` href, so tweets that visibly had links captured none.
2. **Embedded / quote tweets were not captured as links.** A tweet that embeds
   another tweet renders an internal `x.com/<user>/status/<id>` link; the
   scraper's `isInternalTweetLink` filter discarded all x.com links, so
   referenced tweets were lost.

### Problem

External links are the whole point of what the user "keeps," and they were
silently omitted. Embedded tweets are as worth saving as external URLs, yet
were treated as noise.

### Alternatives

- **Keep `t.co` shortlinks as-is** — Rejected: opaque, less useful, and a
  short alias is not the destination the user cares about.
- **Resolve `t.co` via an HTTP redirect** — Rejected for v1: requires network
  work at capture time against the "dumb receiver, no enrichment" principle;
  the display text already carries the real URL.
- **Resolve from the anchor's display text (chosen)** — X renders the true
  destination as the anchor text, so recover it without any network call,
  falling back to the raw `t.co` href when the text isn't a URL.
- **Skip embedded tweets** — Rejected: quote/embedded references are
  first-class content worth keeping.

### Decision

- **External links**: for `t.co` anchors, resolve the real destination from
  the anchor's display text; if the text is not a recognizable URL, fall back
  to the `t.co` href. Trim trailing URL punctuation and dedupe.
- **Embedded/quote tweets**: any internal `/status/<id>` link pointing to a
  **different** tweet than the one being captured is added to `links[]`. The
  current tweet's own status URL is the anchor, never duplicated into links.
- `links[]` is a flat mixed list of external URLs and embedded-tweet status
  URLs.

### Rationale

- Captures what the user actually wants to keep with no network calls and no
  server-side enrichment.
- Keeps the single flat artefact shape and the dumb-receiver contract.

### Consequences

- PRD Rev 2 documents the mixed `links[]` semantics and adds test cases for
  both `t.co` resolution and embedded-tweet capture.
- Extension logic was refactored to `resolveLink(a)` (pure, unit-tested) and a
  status-link branch in `scrapeLinks`.

### Revision triggers

- If `t.co` display text stops carrying the real URL (X changes rendering) —
  revisit redirect resolution or a lookup strategy.
- If a real need emerges to distinguish embedded-tweet links from external
  links in the schema (a `kind` field).
