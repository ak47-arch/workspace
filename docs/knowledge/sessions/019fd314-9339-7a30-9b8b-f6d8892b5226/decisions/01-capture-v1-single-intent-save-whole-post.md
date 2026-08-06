## Decision: Capture v1 ships a single intent — save the whole post (Intent A)

**Status**: accepted
**Date**: 2026-08-06
**Task**: x-capture-instrument
**Project**: feed-analyser
**Session**: sessions/019fd314-9339-7a30-9b8b-f6d8892b5226/session.jsonl

### Context

The capture instrument's hover "Capture" pill was designed to serve two
intents at once: (A) save the whole post (text + links + embedded tweets), and
(B) save a specific highlighted/selected piece of text. The two-intent, one
button model proved fragile in practice. The highlight read raced the click —
`window.getSelection()` was sampled inside the click handler, after the
mousedown had already collapsed the selection — so `selected_texts` reliably
came back empty. Beyond the bug, the single pill felt unnatural for two
different actions, and there was no UI signalling to highlight first.

### Problem

One pill mapping to two genuinely different targets (a tweet vs. a text
selection) with different timing was both broken and confusing. It was not a
bug to patch in isolation; the action-to-target mapping itself was wrong.

### Alternatives

- **Two-trigger model + standalone text captures (Intent B)**: a separate
  floating "Save text" chip on selection, plus relaxing the schema so text
  captures need no tweet URL. Rejected: adds a second capture path and a more
  complex schema; contradicts the "simpler is what we're about" principle.
- **Two-trigger model, highlights attached to tweets only**: a separate chip
  whose output is attached to a tweet. Rejected: still a second flow, and
  limits saving arbitrary text.
- **Single trigger, whole-post only (chosen)**: one pill, one intent (save
  the whole tweet). User context goes in `notes`. Highlight capture deferred
  out of v1.

### Decision

- The **only** capture flow in v1 is **Intent A: the hover pill saves the
  whole tweet** (text, external links, embedded/quote tweets, notes).
- Standalone text-highlight capture (Intent B) is **out of scope for v1** and
  listed as such in the PRD. It may return later as its own trigger only if
  real use proves it.
- The PRD artefact no longer includes `selected_texts`.

### Rationale

- Matches the product's "lightweight, honest, deliberate" ethos and the
  user's stated preference for the simpler path.
- Eliminates the selection-read race and the two-intent UX confusion entirely.
- Delivers a working end-to-end capture loop sooner.

### Consequences

- `selected_texts` removed from the artefact schema, side panel, and content
  script. Notes carry user context.
- The PRD was revised to Rev 2 to reflect single-intent scope (2026-08-06).
- Any later "save this text" desire is a product-evolution decision, not a v1
  behavior.

### Revision triggers

- If real use shows the user repeatedly wanting to save text that isn't the
  whole tweet — revisit Intent B as a separate trigger.
- If the v1 pill is reopened for a multi-action map.
