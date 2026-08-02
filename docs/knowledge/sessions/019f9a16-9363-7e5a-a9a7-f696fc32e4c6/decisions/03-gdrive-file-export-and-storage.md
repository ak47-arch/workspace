## Decision: GDrive File Export, Dedup, and Metadata Strategy

**Status**: accepted
**Date**: 2026-07-25 23:34
**Project**: survival-infrastructure
**Session**: sessions/019f9a16-9363-7e5a-a9a7-f696fc32e4c6/session.jsonl

### Context

Google Drive files come in two categories: natively downloadable (PDF, images, office docs) and Google-native formats (Docs, Sheets, Slides) that require export. The instruction pipeline already handles `file_upload` with SHA-256 dedup, byte storage, and MIME-type whitelisting. GDrive imports need to fit this same pipeline while preserving origin metadata.

### Problem

How should Google-native formats be exported for storage, how should duplicates be detected, where should GDrive provenance metadata live, and how should the backend fetch the file?

### Alternatives

1. **Export formats**: Considered DOCX (for Docs) and CSV (for Sheets) for editability. Rejected — PDF is universal, layout-preserving, already in `SUPPORTED_UPLOAD_MIME_TYPES`, and works with the existing inline preview (Spec 046). OCR to extract text is deferred as out-of-scope.

2. **GDrive file_id dedup**: Considered using GDrive `file_id` as the dedup key. Rejected — if a file is updated in Drive, the same `file_id` should produce a fresh import. SHA-256 of content detects actual changes and matches the existing `file_upload` dedup policy.

3. **Top-level metadata fields**: Considered adding `gdrive_file_id`, `gdrive_mime_type` as top-level fields in the source record. Rejected — `file_ref` is already the container for file-level metadata. Adding GDrive fields inside `file_ref` keeps the schema stable and grouped.

4. **`requests` library for download**: Rejected — `urllib.request` is stdlib and sufficient for a single GET request with no advanced features needed.

### Decision

- **Export format**: PDF for all Google-native formats (Docs, Sheets, Slides). The Google Picker's export URL parameter handles the server-side conversion.
- **Dedup**: SHA-256 of downloaded file bytes (identical to `file_upload` policy).
- **Metadata**: GDrive fields stored inside `file_ref`: `gdrive_file_id`, `gdrive_mime_type` (original), `gdrive_web_view_link`, `gdrive_export_format`, `gdrive_last_edited`.
- **Backend download**: `urllib.request` — stdlib, zero new dependencies.
- **Error handling**: Download failure returns 400 with user-facing message about possible token expiry. No retry logic.

### Rationale

PDF is the path of least resistance — it's already supported, previewable, and avoids format-specific branching. SHA-256 dedup is consistent with existing behavior and correct for content identity. Storing GDrive metadata in `file_ref` follows the principle of grouping related data together.

### Consequences

- Google-native formats lose editability (PDF is output-only). Editable formats can be added as a follow-up with a format selector.
- Token expiry is a user-facing friction — acceptable in v1 given the low frequency of imports.
- The service layer needs to download bytes from a URL rather than reading from a multipart upload — a new code path but a simple one.

### Revision triggers

- If users frequently need editable formats from GDrive, add export format selection (the Picker supports multiple export MIME types).
- If token expiry becomes a pain point during normal use, consider having the frontend refresh the token or pass it separately for backend verification.
- If the `urllib.request` call lacks needed features (timeout configurability, proxy support), switch to `requests` or `httpx`.