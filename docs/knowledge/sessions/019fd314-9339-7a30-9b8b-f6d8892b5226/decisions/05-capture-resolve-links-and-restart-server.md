## Decision: Resolve t.co links from display text robustly; restart server after schema changes

**Status**: accepted
**Date**: 2026-08-06
**Task**: [x-capture-instrument](../../../../tasks/x-capture-instrument.md)
**Project**: feed-analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: resolveLink prefers the anchor's title attribute (X sets the real URL), then recovers from the display text with a glued-word-safe extraction: - whitespace-tokenize and m

### Context

During UAT of the recursive capture, two capture-time problems surfaced.

**1. Link resolution glue.** X wraps external links in `t.co` shortlinks but
renders the real URL as the anchor's display text. Sometimes X glues adjacent
tweet text onto that display domain with no whitespace (e.g.
`explee.comAutoGTM`), and the anchor can also carry a tracking param in its
raw href (`https://t.co/VPalOJjjU7?twclid=…`). The original regex absorbed the
glued word into the TLD (`explee.comAutoGTM`) and stored an ugly shortlink too.

**2. Server dropped new fields.** The extension was updated to send the
**Summary**: ## Decision: Resolve t.co links from display text robustly; restart server after schema changes Status: accepted Date: 2026-08-06 Task: x-capture-instrument Project: feed
recursive tree (`children`, `parent_url`), and the new captures stored
correctly in the unit tests — but live saves came back flat (old schema with
`selected_texts`, no `children`). Root cause: the **running uvicorn process**
was started before `server.py` changed, so it was still executing the old
module in memory. The fix was a server restart, not a code change.

### Problem

- Captured links should resolve to clean, real destinations every time —
  including the glued-word and tracking-param edge cases.
- A lone "extension sends X but the data file doesn't reflect it" symptom is
  almost always a **stale server process running pre-change code**, and wastes
  debugging time if not recognized.

### Decision

- **resolveLink** prefers the anchor's `title` attribute (X sets the real URL),
  then recovers from the display text with a **glued-word-safe** extraction:
  - whitespace-tokenize and match a domain (+ optional path);
  - the TLD (last dot-label) is matched **case-sensitively** as 2-24 lowercase
    letters, and any word-char glued after it is trimmed
    (`explee.comAutoGTM → explee.com` while `github.com/tahul/space-rabbit`
    keeps its path);
  - fall back to the raw `t.co` href with tracking params (`?twclid=…`)
    stripped.
- **Operational rule:** after editing `server.py`, **restart the running
  server** — a uvicorn/uvicorn-like process does not pick up on-disk changes.
  When the extension appears to send correct data that isn't reflected in the
  JSONL, check for a stale server process before debugging the extension.

### Rationale

- Gives clean, real destination URLs from display text with no network calls
  and no server-side enrichment, consistent with the dumb-receiver design.
- Naming the server-restart requirement saves future sessions from re-deriving
  the same trap.

### Consequences

- `resolveLink` (and a small `trimGluedDomain` helper) in `content.js` updated
  and verified against the glued, path, title, and tracking-param cases.
- README "Running the server" should note that schema/code changes require a
  server restart.
- Historical lines stored under the old flat schema stay immutable.

### Revision triggers

- If X changes how links render (no display-text URL, title removed) — revisit.
- If a server auto-reload or a manager (e.g. `--reload`) is introduced, this
  operational note becomes unnecessary.
