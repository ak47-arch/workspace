# PRD: X Capture Instrument

**Date**: 2026-08-06 (rev 4; revised from 2026-08-04, original 2026-07-25 20:01)
**Status**: [Final](./manifest.json)
**Project**: feed-analyser
**Vision**: feed_analyser/capture/docs/vision/VISION.md
**Owner**: Feed analyser → capture pivot initiative
**Task**: [x-capture-instrument](../tasks/x-capture-instrument.md)
**Session**: (current session — product-layer skill conversation)
**Decisions**: Recorded inline in this PRD (see Implementation decisions, Architecture, and Program Design sections).

> **Rev 2 — scope clarification (2026-08-06)**: This revision adopts a single
> capture intent (**Intent A: save the whole post**) and drops the standalone
> text-highlight flow (Intent B) from v1 as over-complex. Links now include
> embedded/quote tweets, and `t.co` shortlinks resolve to their real
> destination. See the updated Implementation decisions, User stories, and
> Artefact schema sections.
>
> **Rev 3 — recursive context capture (2026-08-06)**: A tweet's value is often
> in its context — a few comments (and the links inside them) carry real
> insight. Because **a comment is itself a tweet**, capture becomes
> **recursive**: the user picks a *few* comments to keep alongside the post,
> and each selected comment is captured with the exact same mechanism as the
> tweet, nested into a recursive tree (`children`). The whole-post flow stays
> the single intent; curation is just *choosing which nodes* to keep. The UX
> stays minimal — one Capture pill reused down the tree, plus a small capture
> strip while adding comments. See the Artefact schema, User stories, and
> Implementation decisions sections.
>
> **Rev 4 — forward UX: panel-as-live-view (2026-08-06)**: The side panel is
> a **live view of a capture in progress**, not a one-shot form. Capturing the
> root opens the panel and keeps the capture open; comments below show the same
> Capture pill and clicking one adds it to the growing tree (toggle to remove).
> There is no separate strip — the panel doubles as the live tree + Save. See
> the new "Forward UX" section and updated Implementation decisions rows 16,
> 19–20.

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
│   • tweet URL       │
│                     │
│ Side panel:         │
│   • reviews data    │
│   • toggles links   │
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

1. **Manual capture (Intent A — whole post)**: A user is browsing X.com and sees a tweet worth saving. They hover over the tweet, a "Capture" pill appears. Clicking it opens the side panel pre-filled with the tweet text, its URLs (external links, resolved to real destinations), and any embedded/quote tweets. The user can review, add notes, then click Save. The artefact is POSTed to the local server and appended to `artefacts.jsonl`. This is the single capture flow.

2. **Recursive context capture (curated comments)**: The user sees a tweet whose *comments* carry value — a few specific replies, and links inside them. They click the **Capture** pill on the root tweet. The **side panel opens and the capture stays in progress**. The user scrolls the comments below; every comment shows the **same Capture pill** on hover. Clicking a comment adds it to the capture, nested under its real parent, with a subtle on-page highlight and a live update in the panel's indented tree. Clicking the pill again removes it. When done, the user clicks **Save** in the panel, which POSTs the whole tree and resets for the next capture. Only the *curated* comments are kept — never the whole thread.

3. **Server offline UX**: The user clicks Save but the local server is not running. The side panel shows "Server offline — restart and try again." The data stays in the panel. The user starts the server and clicks Save again.

4. **Auto-scrape failure**: The extension cannot scrape the tweet text (DOM changed, page structure differs). The panel shows a yellow warning "Could not auto-scrape tweet text." The Save button remains active — links and notes are still saved. The tweet URL always serves as the anchor.

5. **Dedup**: The user captures the same tweet twice, possibly with different notes or at different times. Both artefacts are saved independently with separate `captured_at` timestamps. No dedup.

6. **Multiple captures in one session**: The user browses X and captures 5-10 tweets (or conversations). Each capture resets the panel for the next. The side panel persists across page navigations.

## Implementation decisions

| # | Decision | Value | Rationale |
|---|----------|-------|-----------|
| 1 | **Product model** | Thin extension + dumb server + decoupled backend apps | Clean separation of concerns. Extension captures, server stores, backend apps process. Each can evolve independently. |
| 2 | **Capture trigger** | Manual only — a single hover pill, used for the root tweet and recursively for curated comments | No auto-capture. High signal, intentional. One affordance does the whole-post flow and comment curation. |
| 3 | **Extension platform** | Chrome MV3, unpacked, not published | Personal tool on Brave (Chromium). No marketplace concerns. |
| 4 | **Side panel** | Chrome `sidePanel` API | Native browser UI, persists across navigations. Cleaner than injecting into X's DOM. |
| 5 | **Server** | Local FastAPI, single POST endpoint | Familiar stack, runs alongside extension. No auth, no internet dependency. |
| 6 | **Storage format** | JSONL (JSON Lines) | Append-only, simple to read/write, portable. Port to proper storage later. |
| 7 | **Server role** | Dumb receiver only | Appends to JSONL, returns 200. No enrichment, no dedup, no LLM calls at capture time. |
| 8 | **Dedup** | Append — independent artefacts | Each capture is its own artefact. Downstream apps decide what to do. |
| 9 | **Server offline** | Show error in side panel, keep data | Simple. No queuing, no retry logic. Personal tool — user controls the server. |
| 10 | **Auto-scrape failure** | Allow save, show yellow warning | Tweet URL is always the anchor. Links and notes still worth saving. |
| 11 | **Artefact shape (recursive)** | `{ tweet_url, author, tweet_text, links[], children[], notes, captured_at }` — each node is self-similar | A comment is a tweet: every node carries the same fields and nests via `children` into a recursive tree. Covers a curated post + its selected context in one traversable record. |
| 12 | **Links include embedded/quote tweets** | Each node's `links[]` holds external URLs (resolved from `t.co`) plus URLs of any embedded/quote tweets | A tweet often references other tweets; those are as worth keeping as external URLs. The node's own URL is the anchor, never a link. |
| 13 | **Recursive curation, not text-highlight** | The capture flow is recursive: the same pill captures a comment as a node nested under its parent. The user keeps only *curated* comments; there is no arbitrary-text highlight in v1 | Replaces the earlier "Intent B / selected text" idea. A comment is a tweet, so it reuses the whole-post capture mechanism; curation = choosing which nodes to keep. Notes cover user context. |
| 14 | **Data lifecycle** | Read-only after capture | Artefacts are immutable. Downstream apps read and process independently. |
| 15 | **Legacy code** | Archived under `archive/` | Everything preserved, nothing deleted. Clean slate for new capture system. |
| 16 | **One pill, reused down the tree** | A single Capture pill captures a root tweet *and* any comment; the tree nests by DOM parent. Panel is the live view | Keeps UX minimal — one intent, one affordance, no Save/Curate split, no toolbar counter or tree-builder. The tree "emerges from where you click," never constructed explicitly. |
| 19 | **Panel-as-live-view** | The side panel is the live view of a capture in progress. Capturing the root opens the panel and keeps the capture open; adds update the tree live | No separate strip/toolbar. One fewer piece of UI. The panel is the tree view + the Save button. |
| 20 | **Toggle-to-remove** | Clicking the pill on an already-added comment removes it (same gesture toggles) | No separate per-node remove UI in v1. Accidental adds are undone with the same click. |
| 17 | **Recursive depth** | Unlimited depth in the schema; curation chooses how deep | `children` is a recursive `array<node>`; the user only adds what they click, so they control depth implicitly. |
| 18 | **Parent linkage** | Every node carries `parent_url` (null for the root); plus `children` for in-tree order | Lets a node be re-attached to the real thread even if an intermediate comment isn't captured, and enables flat traversal/rebuild. |

## Artefact schema (recursive tree)

Each node is a self-similar capture record; the root is the tweet, and `children` hold the curated comments (which may themselves have `children`). Only curated nodes are kept.

```json
{
  "tweet_url": "https://x.com/user/status/123456",
  "author": "@user",
  "tweet_text": "Full tweet text auto-scraped from DOM",
  "links": ["https://github.com/owner/repo", "https://x.com/other/status/999"],
  "parent_url": null,
  "notes": "User's own context added in side panel",
  "children": [
    {
      "tweet_url": "https://x.com/commenter/status/789",
      "author": "@commenter",
      "tweet_text": "A curated comment with real insight",
      "links": ["https://arxiv.org/abs/1234"],
      "parent_url": "https://x.com/user/status/123456",
      "notes": "",
      "children": [
        {
          "tweet_url": "https://x.com/reply/status/790",
          "author": "@reply",
          "tweet_text": "A curated reply nested under the comment",
          "links": [],
          "parent_url": "https://x.com/commenter/status/789",
          "notes": "",
          "children": []
        }
      ]
    }
  ],
  "captured_at": "2026-08-03T14:30:00Z"
}
```

One JSON object per line in `artefacts.jsonl`.

Every node:
- has the **same shape** as the root — `tweet_url`, `author`, `tweet_text`, `links[]`, `parent_url`, `notes`, `children[]` (only the root carries `captured_at`, stamped by the server)
- keeps **its own** `links[]` — external URLs (resolved out of `t.co`) plus embedded/quote tweet URLs; comment links stay attributed to that node, never folded into the root
- `parent_url` links it back to the real thread even when intermediate comments aren't captured
- `tweet_url` of that node is its own anchor, never duplicated into its `links[]`

## Forward UX (panel-as-live-view)

From the moment the root is captured, the side panel is a **live capture in
progress** — never a one-shot form. On the tweet's detail page, replies render
below and every comment shows the same Capture pill on hover.

1. **Capture the root** → panel opens, capture stays open, anchored to that root.
2. **Comments show the same pill on hover.** One affordance, one meaning: *add
   this tweet to the current capture.*
3. **Click a comment** → added, nested by its real position (DOM parent). Two
   forms of feedback so you always know what's kept:
   - **On-page:** the comment gets a subtle accent/highlight (no tree-builder).
   - **In panel:** the indented tree grows live under the root.
4. **Click the pill again** → removes it (same gesture toggles; no per-node remove UI).
5. **Save in the panel** finishes it — one POST of the whole tree → capture
   completes → panel resets for the next one.
6. **The root pill is inert** while its capture is open; capturing an unrelated
   root *replaces* the current capture. Whether a hovered tweet is a comment of
   the current root is disambiguated by DOM containment.

### Locked decisions

- **A. Nesting display** — indent by the captured-ancestor chain; `parent_url`
  preserves the true position even when an intermediate comment isn't captured.
- **B. Context-sensitivity** — comment curation happens on the detail page
  (comments visible there). Capturing from the timeline yields just the single
  node; there are no comments to add, so no confusion.
- **C. On-page highlight** — selected comments get a subtle accent while
  scrolling, so curation is visible without a tree-builder.
- **D. Toggle-to-remove only** — re-clicking the pill removes; no panel remove ×
  in v1.
- **E. Live panel updates** — the panel mirrors the growing capture on every add.

## Architecture

**Data flow (text-only, minimal, recursive)**

```
User on x.com (detail page)
   │  hover tweet → Capture pill (root) → panel opens, capture in progress
   ▼
Extension (content.js) scrapes root node: tweet_url, author, tweet_text, links
   │  user scrolls comments; each shows the same Capture pill
   ▼
Click a comment → scraped with the same node scraper (parented by DOM)
   │  nested into children[] automatically; on-page highlight + live panel tree
   ▼
Save in panel → sidepanel.js  POST /api/capture  { root node tree }
   │
   ▼
Server (server.py): validate recursively → stamp captured_at on root →
   append line to artefacts.jsonl → 200
```

**Endpoint contract**

- `POST /api/capture`
- Request body: artefact JSON (a recursive node tree), `Content-Type: application/json`
- Success: `200` + `{ "status": "saved", "captured_at": "..." }` — nothing else is done (no enrichment, no analysis, no dedup)
- Failure: `400` when the payload is missing/invalid required fields (validated **recursively** — every nested node must have a `tweet_url`); if the server is unreachable the extension shows "server offline" and preserves the data in the panel
- No other routes — no GET, no list, no resource id

**Data model shape**

- One JSON object per line, appended to `artefacts.jsonl`
- `captured_at` is stamped by the **server** on the root node on receipt (accurate save-time); child nodes inherit the capture context via nesting
- A **recursive node tree**: every node is `{ tweet_url, author, tweet_text, links[], parent_url, notes, children[] }`; `children` is recursive, so a curated comment can itself carry curated replies
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
│   ├── content.js           # on x.com: single Capture pill (hover); recursive node scraper; open-capture state
│                        #   scrapeNode(tweetEl, parentUrl) -> node {url, author, text, links, parent_url, notes, children}
│   ├── sidepanel.html       # panel UI: indented tree review + notes + Save
│   ├── sidepanel.js         # render tree, gather notes, submit recursive root → POST /api/capture
│   └── background.js        # service worker: keep panel state across navigation
└── server/
    ├── server.py            # FastAPI: POST /api/capture → recursive validate → append artefacts.jsonl → 200
    ├── artefacts.jsonl      # data (gitignored)
    └── tests/
        └── test_capture.py  # unit tests: valid/nested → 200 + line; invalid → 400
```

**Key types & signatures — server**

- `POST /api/capture` handler: `capture(artefact: dict) -> JSONResponse` — validates the tree **recursively** (`tweet_url` is required on the root and every nested `children` node; empty `tweet_text` allowed), stamps `captured_at` on the root, appends, returns 200
- `append_artefact(artefact: dict, path: str = "artefacts.jsonl") -> None` — append mode, write `json.dumps(...) + "\n"`, flush

**Key types & signatures — extension**

- `content.js`: `scrapeNode(tweetEl, parentUrl) -> Node` — a **recursive** node scraper (tweet_url, author, tweet_text, links, parent_url, notes, children[]). The root is scraped with `parentUrl = null`; each selected comment is scraped with its DOM-derived parent. `scrapeLinks(tweetEl)` = external URLs resolved from `t.co` + embedded/quote tweet status URLs (per node). Exposes the single Capture pill on hover; tracks the open-capture state (root + growing tree) and live-updates the panel; toggles add/remove; applies on-page highlight to selected comments.
- `sidepanel.js`: renders the recursive tree as an indented list; gathers notes; `submit(rootNode) -> Promise<Response>` — `fetch("http://127.0.0.1:8765/api/capture", POST)`; on network failure show "server offline" and keep the data in the panel
- `background.js`: relays messages between content and panel so the panel survives navigation

**Notes**

- No shared code between extension and server — the only contract is the JSON over `POST /api/capture`
- Server dependencies: FastAPI (+ uvicorn); tests use `pytest` + `httpx`
- Extension is unpacked (Chromium/Brave), not published; no marketplace concerns

## Vertical Slicing (guiding principle)

End-to-end vertical slices are preferred over a horizontal stack-order build (all server first, then all extension). Recommended slicing for implementation:

1. **Slice 1 — the spine (server)**: `POST /api/capture` validates a tree (recursively: every nested node must have a `tweet_url`), appends to `artefacts.jsonl`, returns 200. Verified with a unit test and a raw `curl` POST. Already demoable on its own.
2. **Slice 2 — capture-to-store end to end**: on the detail page, `content.js` scrapes a root tweet → panel opens, user adds a couple of comments (live tree) → `sidepanel.js` submits the nested tree → server appends → a line lands in `artefacts.jsonl`. The full recursive path works.
3. **Slice 3 — panel niceties**: notes field, indented tree rendering, and the "server offline" error state.

Each slice leaves the system demoable end-to-end; no layer is completed in isolation.

## Testing decisions

The feature will be tested at two levels:

1. **Server unit test**: Verify the POST endpoint accepts a valid artefact, appends to JSONL, and returns 200. Verify invalid payloads return 400. Single test file, no framework beyond `python -m pytest` + `httpx` or `requests`.

2. **Manual extension test**: Load the unpacked extension in Brave, navigate to X, capture a tweet, verify side panel opens with correct data, submit, verify JSONL line. No automated browser tests — this is a personal tool.

### Test cases

- Server: POST valid single-node artefact → 200 + line in JSONL
- Server: POST a **nested tree** (root + curated comment + reply) → 200, child nodes intact and correctly nested
- Server: POST missing required field → 400; child node missing `tweet_url` → 400 (recursive validation)
- Server: POST to stopped server → connection refused (extension handles this)
- Extension: Click capture pill on tweet → panel opens with scraped root
- Extension: Capture root then click a comment → the comment nests under the root (and a reply nests under the comment)
- Extension: Tweet/comment with embedded/quote tweet → its `x.com/.../status/...` URL appears in that node's links
- Extension: Link rendered as `t.co` shortlink → links show the real destination URL
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
- **Standalone text-highlight capture**: Selecting/highlighting arbitrary text to save it separately is not in v1. Curation of *whole* comments (which are tweets) via the recursive flow replaces that idea; user context goes in `notes`. May return later as its own trigger if real use proves it.
- **Capturing the whole thread**: Not included — only *curated* comments are captured. "Capture all comments" is never done.
- **Per-node notes / per-node remove / link toggling per node**: Not in v1. One Notes box for the capture; comment links are captured with the node and shown flat. May be added later if curation precision demands it.
- **Tweet engagement (like, reply, retweet)**: Not captured. Only the tweet's visible content.
- **Multi-user support**: Single user, single machine.

## Further notes

### Naming

The new application is called **capture** (directory: `capture/`). The extension lives at `capture/extension/`, the server at `capture/server/`. This naming reflects the core action: capture artefacts from X and store them.
