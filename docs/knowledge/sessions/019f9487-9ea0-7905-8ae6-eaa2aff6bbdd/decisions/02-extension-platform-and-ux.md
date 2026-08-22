## Decision: Chrome MV3 extension with manual capture via side panel

**Status**: accepted
**Date**: 2026-07-25 20:01
**Project**: feed-analyser
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Platform: Chrome MV3, unpacked, not published. - Trigger: Manual only.

### Context

The capture instrument needs a front-end that lives inside the user's browser, on X.com, and allows manual capture of tweet artefacts. The user uses Brave (Chromium-based) and does not plan to publish the extension.

### Problem

What platform and UX model best serves a personal, single-user browser capture tool?

### Alternatives

1. **Firefox extension** — rejected. The user is on Brave (Chromium). No benefit to supporting Firefox.
2. **Injected overlay on X page** — rejected. Fighting X's DOM for z-index and positioning is fragile. Side panel is a native browser UI that persists across navigations.
3. **Chrome popup (action popup)** — rejected. A popup closes when you click outside it. A side panel stays open as you browse.
4. **Chrome sidePanel API** — chosen. Native, persistent, has its own HTML page, available since Chrome 114.
5. **Published on Chrome Web Store** — rejected. Personal tool, single user. Loaded unpacked from source.

### Decision

- **Platform**: Chrome MV3, unpacked, not published.
- **Trigger**: Manual only. A floating "Capture" pill appears on tweet hover. Clicking it opens the side panel.
- **Review UI**: Chrome `sidePanel` API. A dedicated HTML page that shows the scraped data, allows text selection on the page (auto-populates), toggling links, writing notes, and submitting.
- **No auto-capture**: Every capture is intentional.

### Rationale

Manual capture keeps signal high — only tweets the user actively chooses to save end up in the data. The side panel is the right UX for review-before-submit because it persists as the user browses. Chrome MV3 is the only future on Brave/Chrome. Unpacked loading is a one-time step in `chrome://extensions` — fine for a personal tool.

### Consequences

- Extension is not portable to Firefox or Safari without rewriting parts.
- Side panel HTML must be a separate file bundled with the extension (MV3 requirement).
- The capture pill relies on DOM detection of tweet elements — X's DOM changes will require maintenance.

### Revision triggers

- If the user switches to Firefox or Safari as their primary browser.
- If Chrome kills the sidePanel API or changes MV3 in ways that break the architecture.
- If the manual-only capture is too tedious and misses too much data → reconsider a bookmarklet-based bulk import as a supplement, never auto-capture.
