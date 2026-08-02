# PRD: X Capture Instrument

**Date**: 2026-07-25 20:01
**Status**: Draft
**Project**: feed-analyser
**Vision**: feed_analyser/capture/docs/vision/VISION.md
**Owner**: Feed analyser → capture pivot initiative
**Session**: (current session — product-layer skill conversation)
**Decisions**: All decisions recorded inline in this PRD (see Implementation decisions section).

---

## Problem statement

The feed_analyser application was built to collect content from Twitter and YouTube, classify it, and surface insights through a dashboard. In practice, only one part works reliably: the browser console scraper that dumps visible tweets into a JSON file, which is then ingested into SQLite. The dashboard, knowledge graph, GitHub scout, idea workbench, and all other features are unused by the sole user.

The core problems:

1. **Batch collection is low-signal.** Tweets are collected in bulk and stored in SQLite without semantic context. When agents try to reason over the data, they hit SQL's lack of semantic/vector retrieval — the data model doesn't support the analysis users want to do.

2. **Auth restrictions block retrospective analysis.** X/Twitter does not allow headless access to comments, threads, or full tweet context. By the time data is collected and stored, the useful context (comments, related tweets, author profile) is inaccessible without the user being logged into the browser.

3. **The UX doesn't match the user's workflow.** The user spends time in X's native interface, not in a separate dashboard. A standalone web dashboard adds friction — capture and review should happen where the content is consumed.

4. **5,979 lines of code, 5 containers, 1 user.** The application is over-engineered for its actual usage. Most features exist speculatively and were never validated against real use.

## Solution overview

Replace the feed_analyser application with a **capture instrument** — a thin Chrome extension paired with a minimal local server. The extension is the only interface the user touches; the server is a dumb receiver. Decoupled backend applications (built in a separate phase) read the collected data and do whatever analysis or workflow execution is needed.

Architecture:

```
User on X.com
      │
      ▼ (clicks "Capture" pill)
┌─────────────────────┐
│   EXTENSION (thin)  │
│                     │
│ Auto-scrapes:       │
│   • tweet text      │
│   • links           │
│   • visible comments│
│   • tweet URL       │
│                     │
│ Side panel:         │
│   • reviews data    │
│   • highlights text │
│   • adds notes      │
│   • submits         │
└─────────┬───────────┘
          │ POST /api/capture
          ▼
┌─────────────────────┐
│   LOCAL SERVER      │
│   (dumb receiver)   │
│                     │
│  Appends to         │
│  artefacts.jsonl    │
└─────────┬───────────┘
          │ (read-only)
          ▼
┌─────────────────────┐
│   BACKEND APPS      │ ← Phase 2 — decoupled, independent
│   (multiple)        │
└─────────────────────┘
```

Key principle: **the capture pipeline ends at the JSONL file.** The server does nothing after writing. Backend applications will read the JSONL and do their own thing.

## User stories

1. **Manual capture**: A user is browsing X.com and sees a tweet worth saving. They hover over the tweet, a "Capture" pill appears. Clicking it opens the side panel pre-filled with the tweet text, extracted links, and any visible comments. The user can add notes, toggle links, select additional text on the page (which auto-populates), then click Save. The artefact is POSTed to the local server and appended to `artefacts.jsonl`.

2. **Server offline UX**: The user clicks Save but the local server is not running. The side panel shows an error message: "Server offline — restart and try again." The data stays in the panel. The user starts the server and clicks Save again.

3. **Auto-scrape failure**: The extension cannot scrape the tweet text (DOM changed, page structure differs). The panel shows a yellow warning "Could not auto-scrape tweet text." The Save button remains active — the user can still save links, selected text, and notes. The tweet URL always serves as the anchor.

4. **Dedup**: The user captures the same tweet twice, possibly with different notes or at different times. Both artefacts are saved independently with separate `captured_at` timestamps. No dedup. Downstream applications can handle merging if needed.

5. **Multiple captures in one session**: The user browses X and captures 5-10 tweets. Each capture opens the side panel, the user reviews and saves, the panel resets for the next capture. The side panel persists across page navigations.

## Implementation decisions

| # | Decision | Value | Rationale |
|---|----------|-------|-----------|
| 1 | **Product model** | Thin extension + dumb server + decoupled backend apps | Clean separation of concerns. Extension captures, server stores, backend apps process. Each can evolve independently. |
| 2 | **Capture trigger** | Manual only — hover pill on tweet | No auto-capture. High signal, intentional. |
| 3 | **Extension platform** | Chrome MV3, unpacked, not published | Personal tool on Brave (Chromium). No marketplace concerns. |
| 4 | **Side panel** | Chrome `sidePanel` API | Native browser UI, persists across navigations. Cleaner than injecting into X's DOM. |
| 5 | **Server** | Local FastAPI, single POST endpoint | Familiar stack, runs alongside extension. No auth, no internet dependency. |
| 6 | **Storage format** | JSONL (JSON Lines) | Append-only, simple to read/write, portable. Port to proper storage later. |
| 7 | **Server role** | Dumb receiver only | Appends to JSONL, returns 200. No enrichment, no dedup, no LLM calls at capture time. |
| 8 | **Dedup** | Append — independent artefacts | Each capture is its own artefact. Downstream apps decide what to do. |
| 9 | **Server offline** | Show error in side panel, keep data | Simple. No queuing, no retry logic. Personal tool — user controls the server. |
| 10 | **Auto-scrape failure** | Allow save, show yellow warning | Tweet URL is always the anchor. Links and notes still worth saving. |
| 11 | **Artefact shape** | `{ tweet_url, author, tweet_text, links[], selected_texts[], notes, captured_at }` | Minimal. Covers all signal at capture time. Notes field for user context. |
| 12 | **Data lifecycle** | Read-only after capture | Artefacts are immutable. Downstream apps read and process independently. |
| 13 | **Legacy code** | Archived under `archive/` | Everything preserved, nothing deleted. Clean slate for new capture system. |

## Artefact schema

```json
{
  "tweet_url": "https://x.com/user/status/123456",
  "author": "@user",
  "tweet_text": "Full tweet text auto-scraped from DOM",
  "links": ["https://github.com/owner/repo", "https://arxiv.org/abs/1234"],
  "selected_texts": ["user-highlighted portion", "relevant comment text"],
  "notes": "User's own context added in side panel",
  "captured_at": "2026-08-03T14:30:00Z"
}
```

One JSON object per line in `artefacts.jsonl`.

## Testing decisions

The feature will be tested at two levels:

1. **Server unit test**: Verify the POST endpoint accepts a valid artefact, appends to JSONL, and returns 200. Verify invalid payloads return 400. Single test file, no framework beyond `python -m pytest` + `httpx` or `requests`.

2. **Manual extension test**: Load the unpacked extension in Brave, navigate to X, capture a tweet, verify side panel opens with correct data, submit, verify JSONL line. No automated browser tests — this is a personal tool.

### Test cases

- Server: POST valid artefact → 200 + line in JSONL
- Server: POST missing required field → 400
- Server: POST to stopped server → connection refused (extension handles this)
- Extension: Click capture pill on tweet → side panel opens with scraped data
- Extension: Highlight text on page → appears in selected_texts
- Extension: Submit with server offline → error shown, data preserved

### Non-goals

- No automated end-to-end browser tests (personal tool, not published)
- No load testing (single user)
- No CI/CD (unpacked extension, no marketplace)

## Out-of-scope items

- **Backend applications**: LLM analysis, semantic search, workflows, digests — all phase 2. The capture pipeline ends at JSONL.
- **Storage infrastructure**: Vector DB, PostgreSQL, or any semantic storage. Deferred — JSONL is the interim format.
- **YouTube/Gmail/GDrive ingestion**: Not part of this extension. The capture instrument is X/Twitter only. Other sources may be added later as separate extensions or ingestion paths.
- **Historical data migration**: The existing ~1,200 tweets in `archive/backend/data.db` stay where they are. Migration is a separate effort when there's a clear need and a clear target format.
- **Firefox/Safari support**: Chrome (Brave) only. Personal tool.
- **Web Store publication**: Not published. Loaded unpacked.
- **Auto-capture**: Explicitly not included. Manual only.
- **Tweet engagement (like, reply, retweet)**: Not captured. Only the tweet's visible content.
- **Multi-user support**: Single user, single machine.

## Further notes

### Deprecation

The old feed_analyser code has been moved to `archive/`. Everything is preserved — the code, data, specs, and documentation — but it is no longer active. The `capture/extension/` and `capture/server/` directories are where new development happens.

### Existing data

The `archive/backend/data.db` contains ~1,200 previously ingested tweets. When backend applications are built (phase 2), they can read from both the old SQLite DB and the new JSONL file. This is an integration detail for phase 2.

### Naming

The new application is called **capture** (directory: `capture/`). The extension lives at `capture/extension/`, the server at `capture/server/`. This naming reflects the core action: capture artefacts from X and store them.