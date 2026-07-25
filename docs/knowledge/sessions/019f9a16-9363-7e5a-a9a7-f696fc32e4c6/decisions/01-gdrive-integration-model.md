## Decision: GDrive Integration Model and Source Type

**Status**: accepted
**Date**: 2026-07-25
**Session**: sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/session.jsonl

### Context

The survival-infrastructure instruction pipeline captures operational guidance from multiple source types (`freeform`, `url_note`, `citation_note`, `file_upload`). The new task extends it to ingest documents from Google Drive. GDrive hosts reference material (strategy docs, frameworks, PDFs) that belongs in the instruction store, not the event pipeline.

### Problem

How should GDrive files be selected, authenticated, and represented in the instruction pipeline? This covers integration modality (manual vs automated), source type identity (reuse vs new), and API surface (dedicated vs shared endpoint).

### Alternatives

1. **Folder sync / headless monitoring**: Poll a configured GDrive folder, auto-import new files. Rejected — adds OAuth token persistence, background worker complexity, and conflicts with the manual-curation ethos of the instruction pipeline. More appropriate for Phase 7 RAG at scale.

2. **Reuse `file_upload` source type**: Send GDrive file through the existing file upload endpoint after frontend-side download. Rejected — loses GDrive provenance metadata (file ID, original format, view link). Downstream consumers (audit, future retrieval) cannot distinguish Drive-origin files from local uploads without guessing.

3. **Dedicated `/api/instructions/gdrive` endpoint**: Separate route for GDrive imports. Rejected — unnecessary surface area. The existing `ingest_source()` dispatcher already switches on `source_type`. A new `gdrive_file` handler fits the same pattern with no new routes.

### Decision

- **Integration model**: Google Picker API for browser-driven, manual file selection. No background sync.
- **Source type**: New `gdrive_file` enum value, distinct from `file_upload`.
- **Endpoint**: Reuse `POST /api/instructions/sources`. The `source_type` switch in `ingest_source()` dispatches to a new `_ingest_gdrive_file()` handler.

### Rationale

The Google Picker is the laziest path with the right properties: it handles OAuth, file browsing, search, and export URL generation without any backend token management. A dedicated source type preserves traceability for audits and future retrieval systems without over-engineering the data model. Reusing the existing endpoint keeps the API surface small and the module boundary clean.

### Consequences

- The frontend needs a new `source_type` form option and Google Picker JS integration.
- The backend service gains one new private method (`_ingest_gdrive_file()`) but no new public API.
- Existing `file_upload` behavior is completely unchanged.
- Downstream tools can filter by `source_type: "gdrive_file"` to find Drive-origin content.

### Revision triggers

- When the instruction pipeline adds background sync or folder monitoring, the integration model should be revisited for a headless OAuth + Drive API path.
- If GDrive import volume exceeds manual picker throughput, consider batch import or folder-level operations.