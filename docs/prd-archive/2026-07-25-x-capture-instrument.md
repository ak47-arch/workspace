# PRD: X Capture Instrument

**Date**: 2026-08-04 (revised; original 2026-07-25 20:01)
**Status**: Draft
**Project**: feed-analyser
**Vision**: feed_analyser/capture/docs/vision/VISION.md
**Owner**: Feed analyser → capture pivot initiative
**Task**: x-capture-instrument
**Session**: (current session — product-layer skill conversation)
**Decisions**: Recorded inline in this PRD (see Implementation decisions, Architecture, and Program Design sections).

---

## Problem statement

There is no reliable way to save X/Twitter content the user cares about *as they browse*. The prior feed_analyser effort was over-engineered and unused, so it is archived. What the user needs is a lightweight, honest way to capture a post (text and links), add their own notes, and keep it durably — with the analysis of that content deliberately left to separate, later tools.

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

## Architecture

**Data flow (text-only, minimal)**

```
User on x.com
   │  hover tweet → Capture pill
   ▼
Extension (content.js) scrapes: tweet_url, author, tweet_text, links
   │  opens side panel (background.js keeps state across navigation)
   │  user adds selected text + notes
   ▼
sidepanel.js  POST /api/capture  {tweet_url, author, tweet_text, links, selected_texts, notes}
   │
   ▼
Server (server.py): validate → stamp captured_at → append line to artefacts.jsonl → 200
```

**Endpoint contract**

- `POST /api/capture`
- Request body: artefact JSON (below), `Content-Type: application/json`
- Success: `200` + `{ "status": "saved", "captured_at": "..." }` — nothing else is done (no enrichment, no analysis, no dedup)
- Failure: `400` when the payload is missing/invalid required fields; if the server is unreachable the extension shows "server offline" and preserves the data in the panel
- No other routes — no GET, no list, no resource id

**Data model shape**

- One JSON object per line, appended to `artefacts.jsonl`
- `captured_at` is stamped by the **server** on receipt (accurate save-time)
- No `id`, no `type`, no metadata envelope — a flat, minimal record. New fields are added to later lines as needed and never break existing ones
- No dedup / uniqueness — each capture appends independently
- Scope is **text-only**; images, screenshots, and binary/blob storage are explicitly out of scope for v1

**Storage & config**

- Single data file `artefacts.jsonl` beside the server (`server/artefacts.jsonl`), opened in append mode, write + flush per line
- Fixed default port `8765`, overridable only by a single env var (e.g. `CAPTURE_PORT`); no config file, no CLI flags
- `artefacts.jsonl` is gitignored

## Program Design

**File tree (greenfield)**

```
capture/
├── extension/
│   ├── manifest.json        # MV3: content script + side panel + permissions (x.com host)
│   ├── content.js           # on x.com: hover → Capture pill, scrape tweet (url/author/text/links), text highlight
│   ├── sidepanel.html       # panel UI: prefill review + notes + Save
│   ├── sidepanel.js         # render scrape result, gather notes/selection, submit → POST /api/capture
│   └── background.js        # service worker: keep panel state across navigation
└── server/
    ├── server.py            # FastAPI: POST /api/capture → validate → append artefacts.jsonl → 200
    ├── artefacts.jsonl      # data (gitignored)
    └── tests/
        └── test_capture.py  # unit tests: valid → 200 + line; invalid → 400
```

**Key types & signatures — server**

- `POST /api/capture` handler: `capture(artefact: dict) -> JSONResponse` — validates required fields (`tweet_url` is the anchor; empty `tweet_text` allowed), stamps `captured_at`, appends, returns 200
- `append_artefact(artefact: dict, path: str = "artefacts.jsonl") -> None` — append mode, write `json.dumps(...) + "\n"`, flush

**Key types & signatures — extension**

- `content.js`: `scrapeTweet(tweetEl) -> { tweet_url, author, tweet_text, links[] }`; exposes the Capture pill on hover; listens for user text selection
- `sidepanel.js`: `submit(artefact) -> Promise<Response>` — `fetch("http://127.0.0.1:8765/api/capture", POST)`; on network failure show "server offline" and keep the data in the panel
- `background.js`: relays messages between content and panel so the panel survives navigation

**Notes**

- No shared code between extension and server — the only contract is the JSON over `POST /api/capture`
- Server dependencies: FastAPI (+ uvicorn); tests use `pytest` + `httpx`
- Extension is unpacked (Chromium/Brave), not published; no marketplace concerns

## Vertical Slicing (guiding principle)

End-to-end vertical slices are preferred over a horizontal stack-order build (all server first, then all extension). Recommended slicing for implementation:

1. **Slice 1 — the spine (server)**: a `POST /api/capture` endpoint that validates, appends to `artefacts.jsonl`, and returns 200. Verified with a unit test and a raw `curl` POST. Already demoable on its own.
2. **Slice 2 — capture-to-store end to end**: `content.js` scrapes one tweet → `sidepanel.js` submits → server appends → a line lands in `artefacts.jsonl`. The full path works.
3. **Slice 3 — panel niceties**: notes field, selected-text/highlighting, and the "server offline" error state.

Each slice leaves the system demoable end-to-end; no layer is completed in isolation.

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
- **Firefox/Safari support**: Chrome (Brave) only. Personal tool.
- **Web Store publication**: Not published. Loaded unpacked.
- **Auto-capture**: Explicitly not included. Manual only.
- **Tweet engagement (like, reply, retweet)**: Not captured. Only the tweet's visible content.
- **Multi-user support**: Single user, single machine.

## Further notes

### Naming

The new application is called **capture** (directory: `capture/`). The extension lives at `capture/extension/`, the server at `capture/server/`. This naming reflects the core action: capture artefacts from X and store them.