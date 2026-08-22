## Decision: GDrive Auth and Configuration Approach

**Status**: accepted
**Date**: 2026-07-25 23:34
**Project**: survival-infrastructure
**Session**: [session.jsonl](../session.jsonl)
**Summary**: Google credentials live in .env as GOOGLE_DRIVE_API_KEY and GOOGLE_DRIVE_CLIENT_ID. - The Flask app loads them via os.environ.get() in the template context processor or r

### Context

The Google Picker API requires a Google Cloud API key (for the Picker API) and an OAuth 2.0 client ID (for user authentication). These are public credentials (they live in browser JavaScript) but vary per deployment. The survival-infrastructure project uses `.env` + Flask config for runtime configuration.

### Problem

Where and how should Google API credentials be stored, loaded, and delivered to the frontend so they are configurable per deployment, absent from version control, and absent from the page when the feature isn't configured?

### Alternatives

1. **Static JS config file**: Hardcode credentials in a version-controlled JS file. Rejected — credentials differ per deployment and should not be in version control.

2. **Backend API endpoint**: Serve credentials from `GET /api/config/gdrive`. Adds a route and caching consideration. Over-engineered for two static values that don't change at runtime.

3. **Flask config → template injection**: Load from `.env` into Flask app config, pass to `render_template()` as JS globals. Rejected in favor of the same pattern but through the existing config system for consistency with the project's config patterns.

### Decision

- Google credentials live in `.env` as `GOOGLE_DRIVE_API_KEY` and `GOOGLE_DRIVE_CLIENT_ID`.
- The Flask app loads them via `os.environ.get()` in the template context processor or route handler.
- The template renders them as `window.GOOGLE_DRIVE_API_KEY` and `window.GOOGLE_DRIVE_CLIENT_ID` globals.
- When either value is missing/empty, the GDrive import option is hidden from the UI.

### Rationale

Follows the existing project pattern (`SURVIVAL_*` env vars). No new config schema, no new route, no restart orchestration beyond what `.env` already needs. The frontend gating is a single `if (window.GOOGLE_DRIVE_API_KEY && window.GOOGLE_DRIVE_CLIENT_ID)` check — no backend change needed to disable the feature.

### Consequences

- New entries needed in `.env.template`.
- Flask template or context processor needs one-time wiring to pass these values.
- Deployments without Google credentials see no GDrive option — clean degradation.

### Revision triggers

- If OAuth evolves to support backend-driven flows (sync, monitoring), credentials will need server-side storage and refresh token handling, making this decision obsolete.
