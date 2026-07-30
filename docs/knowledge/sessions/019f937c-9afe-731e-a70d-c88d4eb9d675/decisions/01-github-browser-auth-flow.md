## Decision: GitHub Browser Auth Flow for Workspace Restore

**Status**: accepted
**Date**: 2026-07-24
**Project**: workspace-portability
**Session**: sessions/019f937c-9afe-731e-a70d-c88d4eb9d675/session.jsonl

### Context

The workspace-portability Phase 1 restore pipeline (`magic-setup.sh` → `bootstrap-orchestrator.sh` → `restore_workspace.py`) requires a `GITHUB_TOKEN` to clone private repos and download critical snapshots from GitHub Releases. On a fresh machine, the user must manually create a GitHub PAT before they can run the one-command setup. This adds friction to the bootstrap flow, especially for new developers or operators provisioning a machine.

### Problem

Every fresh machine requires the user to:
1. Navigate to GitHub settings
2. Create a fine-grained PAT with `repo` scope
3. Copy the token and pass it to the setup command

This is slow, error-prone, and interrupts the "one command" magic setup experience. The restore drill on themistocles (2026-06-19/20) also showed that different token types (`ghp_`, `gho_`, `github_pat_`) behave inconsistently with git auth methods, adding further friction.

### Alternatives

1. **GitHub CLI (`gh auth login`)** — installs `gh`, then runs its own OAuth flow. Rejected because `gh` is not installed on a blank machine (same chicken-and-egg problem as the PAT). Adding `gh` to the host bootstrap adds another dependency.

2. **Personal Access Token (status quo)** — continue requiring a PAT. Rejected because the whole point is to remove PAT friction from the fresh-machine flow.

3. **GitHub App installation token** — more complex OAuth setup, requires a GitHub App to be installed on the org. Overkill for a single-user workspace.

4. **SSH key-based auth** — user generates and uploads an SSH key to GitHub. Also friction, and SSH keys don't work for GitHub Releases API calls.

5. **GitHub Device Authorization Flow (chosen)** — OAuth device flow designed for CLI/headless auth. User visits a URL, enters a code, authorises. No client secret needed. Works on machines without a browser.

### Decision

Use **GitHub Device Authorization Flow** as the fallback when `GITHUB_TOKEN` is not provided. Implementation:

- A shell script `github-auth-device-flow.sh` in `workspace-portability/` handles the interactive flow (print URL, print code, poll for completion)
- A Python function `device_flow_auth()` in `portability_lib.py` handles the API polling
- Priority: `GITHUB_TOKEN` env var > device flow (backward compatible)
- Scope requested: `repo` (minimum required for cloning private repos + reading release assets)
- OAuth App registered under `ak47-arch` GitHub account, `client_id` baked into script but overridable via `GITHUB_OAUTH_CLIENT_ID` env var
- Token is not persisted — used in-memory for the restore session, discarded after
- URL and code are printed to stdout; no auto-open of browser

### Rationale

- Device flow is the standard OAuth pattern for CLI tools (GitHub CLI, AWS CLI, etc.)
- No client secret needed — the `client_id` is public by design
- Works on headless machines (SSH targets) — user authenticates from their phone/laptop
- Backward compatible — existing `GITHUB_TOKEN` workflows continue unchanged
- Minimal implementation — ~50 lines of Python + ~40 lines of shell
- Re-auth on new terminal sessions is acceptable for now; UX can be improved later if needed

### Consequences

- `magic-setup.sh` and `bootstrap-orchestrator.sh` gain a conditional: if `GITHUB_TOKEN` is unset, call `github-auth-device-flow.sh` to get one
- `restore-workspace.sh` thin wrapper already handles `GITHUB_TOKEN` → `GIT_ASKPASS`; no changes needed there
- `restore_workspace.py` already accepts `--github-token`; no changes needed there
- The OAuth App must be registered and maintained under `ak47-arch` (or transferred to an org)
- Rate limits on the device flow endpoint (GitHub allows 50 device flow requests per hour per client_id) — irrelevant for a restore flow that runs once per machine
- No impact on `sync-repos.sh` or `restore-data.sh` — those still require a token for new terminal sessions

### Revision triggers

- If the token persistence UX becomes a pain point (users re-authing frequently for sync/restore-data)
- If the OAuth App needs to be transferred to an org or different account
- If GitHub deprecates the device flow endpoint
- If the workspace goes fully public (no auth needed for repos)