## Decision: Capture artefact is a recursive node tree — a comment is a tweet

**Status**: accepted
**Date**: 2026-08-06
**Task**: [x-capture-instrument](../../../../tasks/x-capture-instrument.md)
**Project**: feed-analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: The artefact is a recursive node tree.

### Context

The highlight/"selected text" idea resurfaced during design, and on reflection
the underlying need was never *arbitrary text selection* — it is that **a
tweet's value is often in its context**: a few comments (and the links inside
them) carry real insight. The user wants to curate those along with the post,
not copy snippets.

Two earlier PRDs shaped this space:
- PRD Rev 2 dropped standalone text-highlight (Intent B) in favour of a single
  whole-post capture intent.
- The first pass at bringing context back proposed a flat `curated_comments`
  list plus an over-built curation UI (Save/Curate split, toolbar counter,
  collapsible nodes, per-node notes/remove). The user rejected the UI as
  "too many bells and whistles."

### Problem

How do we capture a tweet *and* user-picked comments (recursively, with their
links) without a new "comment" feature and without a complex UI? And how do we
extend the storage so this stays minimal yet traversable?

### Alternatives

- **Flat `curated_comments` list** — Rejected: cannot express replies to
  replies, cannot attribute nested links cleanly, and shared the awkward UI.
- **Per-node hotchpotch schema** (special comment records) — Rejected: adds a
  distinct type instead of reusing the existing, working capture.
- **Capture the whole thread** — Rejected: the user explicitly wants only
  *some* curated comments, not everything.
- **Recursive node tree, comment = tweet (chosen)** — a comment is itself a
  tweet, so it is captured by the *exact same* mechanism as the post and nests
  via `children`.

### Decision

- The artefact is a **recursive node tree**. Every node has the same self-
  similar shape:
  `{ tweet_url, author, tweet_text, links[], parent_url, notes, children[] }`;
  only the root carries `captured_at` (server-stamped).
- `children[]` is a recursive array of nodes, so a curated comment can itself
  carry curated replies to any depth.
- `parent_url` on every node (null for root) lets a node be re-attached to the
  real thread even when an intermediate comment isn't captured, and enables
  flattening/traversal downstream.
- **Recursive capture UX**: one Capture pill is reused down the tree. Capturing
  the root starts a conversation capture (a slim strip: count + Done); clicking
  the same pill on comments nests them by DOM parent. The tree is never
  constructed by the user — it *emerges from where they click*.
- **Only curated nodes are kept** — never the whole thread.

### Rationale

- Directly captures the product need ("a tweet is more than the tweet; its
  curated comments/links are the context") with **no new feature type** — a
  comment *is* a tweet.
- Reuses the existing, already-working capture mechanism and keeps the server
  a dumb receiver (one POST, validate recursively, append).
- Recursive/self-similar structure is trivially traversable (DFS/BFS) for the
  decoupled backend apps.
- Keeps the artefact minimal and keeps attribution (each node owns its links).

### Consequences

- PRD bumped to Rev 3: recursive schema, user stories, implementation
  decisions (rows 2, 11, 13, 16–18), architecture data flow, program design
  (recursive `scrapeNode(tweetEl, parentUrl)`), vertical slicing, tests, and
  out-of-scope (whole-thread capture, per-node notes/remove, per-node link
  toggles, arbitrary-text highlight).
- Implementation (pending): refactor `content.js` to a recursive
  `scrapeNode(tweetEl, parentUrl)` + capture strip; render an indented tree in
  `sidepanel.js`; extend `server.py` validation recursively (every nested node
  needs `tweet_url`); add nested-schema tests.
- The exact capture-strip interaction (strip-first vs panel-immediate) and
  depth/per-node scope are still open UX decisions (see session continuing).

### Revision triggers

- If real use shows the need to capture a *portion* of a comment (text
  highlight within a node), or per-node notes/remove/link-toggling — revisit
  v1 out-of-scope items.
- If entire subthreads should be captured at once — a "capture this reply and
  everything under it" affordance.
