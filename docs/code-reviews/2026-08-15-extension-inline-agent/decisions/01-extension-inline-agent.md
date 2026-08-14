# Decision 01 — extension-inline-agent advisory acceptance (re-review rev 1)

**Task**: extension-inline-agent
**Review session**: 6f5b0d44-d1a3-41f5-b1f9-f4f1202bf1c1
**PR**: ak47-arch/feed_analyser#1 · Head: 93306541dfcbe6218d40d2b8a4bc9afc4e294ab1

## Context

The first review of this PR returned REQUEST_CHANGES for one blocking defect:
on a fresh checkout with no `data/` dir, a plain Save with the agent
unavailable raised an unhandled `FileNotFoundError` → HTTP 500, breaking US5
("agent unavailable … saving still works as today"). Revision 1 fixed exactly
that. This re-review found no remaining blocking issues.

## Decision

The blocking US5 fix is accepted (verified: `append_artefact` now
`target.parent.mkdir(parents=True, exist_ok=True)`; new regression test
`test_save_creates_missing_data_dir`; live POST to a non-existent `data/`
returns 200 and creates the dir + file). The advisory findings from the
original review are re-confirmed as **non-blocking / acceptable-as-is** and
were intentionally left unchanged per the binding "fix exactly what findings
scope" rule:

- `sidepanel.js` Ask-control disabled expression has inverted/ambiguous
  precedence (readability only).
- `index.py` `build_fts_query` is a ~70-line hand-rolled FTS5 MATCH translator
  (justified by the PRD search criteria).
- `/search.total` reflects the capped page, not the true count (COUNT(*) before
  LIMIT if consumers rely on it).
- Reconnect after a mid-capture service restart drops in-memory conversation
  context (acceptable for v1 single-session flow; wire `messages` through on
  reconnect in a later phase).

None of these block release.

## Options considered

- Narrowing the FTS query grammar to reduce `build_fts_query` — rejected as a
  change to this revision; grammar is justified and correct, and a rewrite
  would violate scope.
- Computing true total via COUNT(*) — not required by any consumer in v1;
  deferred as a refinement.

## Consequences

- Task eligible to transition `in-progress → in-review` on APPROVE.
- Real OpenRouter inference + browser side-panel e2e remain UAT items
  (require the user's key and live x.com panel).
