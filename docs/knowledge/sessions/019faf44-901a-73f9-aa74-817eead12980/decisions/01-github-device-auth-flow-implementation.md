## Decision: GitHub Device Authorization Flow Implementation

**Status**: accepted
**Date**: 2026-07-29
**Project**: workspace-portability
**Session**: sessions/019faf44-901a-73f9-aa74-817eead12980/session.jsonl

### Context

The workspace-portability Phase 1 restore pipeline (`magic-setup.sh` → `bootstrap-orchestrator.sh` → `restore_workspace.py`) requires a `GITHUB_TOKEN` to clone private repos and download critical snapshots. On a fresh machine, the user must manually create a PAT — this breaks the "one command" magic setup promise.

PRD `docs/prd-queue/2026-07-24-github-browser-auth-flow.md` specified the solution: a GitHub Device Authorization Flow as fallback when `GITHUB_TOKEN` is absent.

### Problem

- The workspace-portability repo is **private** — so the device flow must work *before* the repo is cloned, meaning `magic-setup.sh` (the curl'd bootstrap script) cannot depend on any file inside the repo
- `magic-setup.sh` is piped via `curl | bash` — stdin is not a terminal, so interactive prompts like `read -p` won't work
- The device flow must work on headless machines (SSH targets) without a browser
- The OAuth App client_id is public by design and can be baked into the script

### Alternatives

1. **Embed device flow logic in `magic-setup.sh` inline** (chosen) — the script contains a self-contained Python heredoc that implements the device flow. No repo dependency.
2. **Reference `github-auth-device-flow.sh` from the repo** — impossible because the repo hasn't been cloned yet when the token is needed.
3. **Use a separate lightweight bootstrap script** — unnecessary complexity; the inline Python approach is clean and self-contained.
4. **Require `GITHUB_OAUTH_CLIENT_ID` env var always** — would force setting an env var on every machine, defeating the purpose. The client_id is baked in as a default, overridable via env var.

### Decision

Implemented the GitHub Device Authorization Flow across four files:

1. **`portability_lib.py`** — `device_flow_auth()` function with full polling logic, error handling (authorization_pending, slow_down, expired_token, access_denied), 5-minute timeout, all output to stderr except the token (to stdout)
2. **`github-auth-device-flow.sh`** (new) — interactive shell wrapper calling `portability_lib.device_flow_auth()`, designed for `GITHUB_TOKEN=$(./github-auth-device-flow.sh)`
3. **`magic-setup.sh`** — self-contained inline Python heredoc implementing the device flow (same logic as `portability_lib.py`), used when `GITHUB_TOKEN` is absent. This is the bootstrap path — no repo dependency.
4. **`bootstrap-orchestrator.sh`** — calls `github-auth-device-flow.sh` from the cloned repo when `GITHUB_TOKEN` is absent (for direct invocation)

The OAuth App was registered under the `ak47-arch` GitHub account with:
- Client ID: `Ov23liwOYpUqSP2bY03Z`
- Device Flow enabled
- Scope: `repo` (minimum required for cloning private repos + reading release assets)

### Rationale

- Inline Python in `magic-setup.sh` solves the chicken-and-egg problem: the script is the *only* file available on a fresh machine, but the device flow must run *before* the private repo can be cloned
- Device flow works on headless machines — user authenticates from any device with a browser (phone, laptop)
- No client secret needed — the flow is public by design
- Backward compatible — existing `GITHUB_TOKEN` workflows continue unchanged
- `GITHUB_OAUTH_CLIENT_ID` env var allows forks to use their own OAuth App

### Consequences

- `magic-setup.sh` grew by ~130 lines (the inline Python heredoc) — acceptable for a bootstrap script
- `restore-workspace.sh` and `restore_workspace.py` required no changes — token flows through `GIT_ASKPASS` and `--github-token` CLI arg as before
- Token is not persisted — re-auth required for new terminal sessions (acceptable for now; can be improved later)
- Rate limit: 50 device flow requests per hour per client_id — irrelevant for a restore flow that runs once per machine

### Revision triggers

- If token persistence becomes a UX pain point (users re-authing frequently for sync/restore-data)
- If the OAuth App needs to be transferred to a different account or organization
- If GitHub deprecates or changes the device flow endpoint
- If the workspace-portability repo becomes public (no auth needed)