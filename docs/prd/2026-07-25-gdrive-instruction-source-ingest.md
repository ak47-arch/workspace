# GDrive Instruction Source Ingest

**Date**: 2026-07-25 23:34
**Status**: [Draft](./manifest.json)
**Project**: survival-infrastructure
**Vision**: survival-infrastructure/docs/technical/VISION.md | survival-infrastructure/docs/technical/TECHNICAL_VISION.md
**Owner**: survival-infrastructure
**Session**: [session.jsonl](../knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/session.jsonl)
**Decisions**:
  - [01-gdrive-integration-model](../knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/decisions/01-gdrive-integration-model.md)
  - [02-gdrive-auth-and-configuration](../knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/decisions/02-gdrive-auth-and-configuration.md)
  - [03-gdrive-file-export-and-storage](../knowledge/sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/decisions/03-gdrive-file-export-and-storage.md)
---

## Problem Statement

The survival-infrastructure instruction pipeline can ingest instruction sources as local file uploads (`file_upload`), but has no way to pull documents from Google Drive. Reference material, strategy documents, frameworks, and other operational guidance often live in GDrive — users currently have to download files locally then upload them manually. This friction discourages use of the instruction pipeline as a central reference store.

## Solution Overview

Add a new `gdrive_file` source type to the existing instruction ingest endpoint that uses the Google Picker API for browser-based file selection and OAuth. When a user selects a file through the Picker, the frontend sends the picker result (download URL, file metadata) to the existing `POST /api/instructions/sources` endpoint. The backend downloads the file bytes and ingests them through the established `file_upload` code path (SHA-256 dedup, bytes persisted under `instructions/uploads/`, record written to `raw_sources.jsonl`).

Google-native formats (Docs, Sheets, Slides) are exported as PDF automatically via the Picker's export URL. GDrive-specific metadata (file ID, original MIME type, Drive view link) is stored inside `file_ref` to preserve provenance.

Google credentials (`GOOGLE_DRIVE_API_KEY`, `GOOGLE_DRIVE_CLIENT_ID`) are configured via `.env` and injected into the HTML template. When unconfigured, the GDrive import option is hidden.

## User Stories

1. **GDrive option in source type selector** — As a user, I can select "Google Drive File" from the instruction source type dropdown in the Instructions panel.

2. **Google Picker file selection** — As a user, selecting "Google Drive File" shows a "Connect to Google Drive" button. Clicking it opens the Google Picker where I authenticate and browse my Drive files.

3. **Import PDF from Drive** — As a user, I can select a PDF from GDrive and import it as an instruction source. The file is ingested, stored, and visible in the instruction list.

4. **Import Google Doc as PDF** — As a user, selecting a Google Doc imports it with automatic PDF export. The record shows the original format (`application/vnd.google-apps.document`) alongside the exported PDF.

5. **Import Google Sheet/Slide as PDF** — As a user, selecting a Google Sheet or Slide imports it with automatic PDF export. Same provenance tracking as Docs.

6. **Provenance metadata** — As a user, the instruction detail page for a `gdrive_file` source shows the original file name, GDrive file ID, the original format, and a clickable link to view the file on Google Drive.

7. **Download option** — As a user, I can download the imported PDF from the instruction detail page, just like any `file_upload` source.

8. **Dedup** — As a user, importing the same file (same SHA-256) twice results in a 409 conflict with a link to the existing record.

9. **Credentials gating** — As a user on a deployment without Google credentials configured, the "Google Drive File" option is hidden from the source type selector.

10. **Expired token handling** — As a user, if the download token expires before the backend fetches the file, I receive a clear error requesting I re-select the file in the Picker.

## Implementation Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Integration model | Google Picker API — browser-driven manual file selection. No background sync. |
| 2 | Source type identity | New `gdrive_file` enum value distinct from `file_upload`. Keeps data model honest for downstream consumers. |
| 3 | Endpoint | Reuse `POST /api/instructions/sources` — the `ingest_source()` dispatcher gets a new `_ingest_gdrive_file()` handler alongside existing `_ingest_text_based()` and `_ingest_file_upload()`. No new routes. |
| 4 | Config mechanism | `GOOGLE_DRIVE_API_KEY` and `GOOGLE_DRIVE_CLIENT_ID` in `.env`, loaded into Flask config, injected as JS globals in the template. Button hidden when absent. |
| 5 | Export format | All Google-native formats (Docs, Sheets, Slides) exported as PDF via the Picker's built-in export URL. No format selection in v1. |
| 6 | Dedup strategy | SHA-256 of downloaded file bytes (same as `file_upload`). GDrive `file_id` is recorded but not used for dedup — content changes should produce a new record. |
| 7 | Metadata location | GDrive-specific fields stored inside `file_ref` alongside standard fields: `gdrive_file_id`, `gdrive_mime_type`, `gdrive_web_view_link`, `gdrive_export_format`, `gdrive_last_edited`. |
| 8 | Backend download | `urllib.request` (stdlib) — no new dependency. Requests the download URL returned by the Picker with embedded access token. |
| 9 | Error handling | Simple: download failure returns 400 with explanation that the token may have expired. No retry logic, no token refresh. |
| 10 | Module boundary | `app.py` remains transport-only. New logic lives in `service.py` (`_ingest_gdrive_file`). Module boundary (`module.py`) unchanged — existing `ingest_source()` dispatches by source_type. |

## Testing Decisions

| Seam | What's tested |
|------|---------------|
| **Service layer** (unit) | `_ingest_gdrive_file()` — valid payload creates record with correct metadata; missing fields return 400; duplicate SHA-256 returns 409; expired/error download URL returns 400; file exceeding `max_upload_bytes` returns 413. |
| **Repository layer** (unit) | GDrive metadata in `file_ref` is persisted and retrievable. |
| **API contract** (integration) | `POST /api/instructions/sources` with `source_type=gdrive_file` and a mock download URL returns 201 with expected response shape. Listing sources includes `gdrive_file` records. Detail returns full GDrive metadata. |
| **Template rendering** (UI test) | Detail page for `gdrive_file` shows file name, GDrive link, download button. Instructions list shows `gdrive_file` badge. GDrive option hidden when config vars absent. |
| **Boundary guard** | Routes delegate to `_instruction_module()`, no direct service/repo imports in `app.py` for GDrive logic. |

## Out of Scope

- Gmail integration (deferred to a later effort)
- Background sync, folder monitoring, or scheduled GDrive polling
- RAG indexing, chunking, embedding, or retrieval (Phase 7)
- OCR for PDF content extraction
- Multiple export format selection (user picks Doc/Docx/TXT)
- Retry logic for download failures or expired tokens
- GDrive file version tracking or incremental sync
- OAuth token persistence beyond the Picker session
- AnythingLLM instruction-store container integration

## Further Notes

- The Google Picker API requires the Picker API and Drive API enabled in the Google Cloud project.
- The OAuth client ID should be of type "Web application" with the app's origin in the authorized JavaScript origins.
- The download URL from the Picker is a Google-signed URL with an embedded access token — it is a one-shot URL valid for a limited time. The backend must fetch it immediately on receipt.
- Existing `file_upload` source type is completely unchanged — zero regression risk.
- The `instructions/` module boundary pattern (app → module → service → repository) is preserved.