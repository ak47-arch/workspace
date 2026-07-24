# PRD: GitHub Browser Auth Flow for Workspace Restore

**Date**: 2026-07-24
**Status**: Draft
**Owner**: Workspace portability initiative
**Session**: `docs/knowledge/sessions/019f937c-9afe-731e-a70d-c88d4eb9d675/session.jsonl`
**Decisions**:
  - `docs/knowledge/sessions/019f937c-9afe-731e-a70d-c88d4eb9d675/decisions/01-github-browser-auth-flow.md`

## Problem statement

The workspace-portability Phase 1 restore pipeline (`magic-setup.sh` → `bootstrap-orchestrator.sh` → `restore_workspace.py`) requires a `GITHUB_TOKEN` to clone private repos and download critical snapshots from GitHub Releases. On a fresh machine, the user must manually:

1. Navigate to GitHub Settings → Developer settings → Personal access tokens
2. Create a fine-grained PAT with `repo` scope
3. Copy the token and pass it to the setup command

This breaks the "one command" magic setup promise. Instead of `curl | bash`, the user needs to first go through a multi-step token creation flow. The restore drill on themistocles (2026-06-19/20) also showed that different token types behave inconsistently with git auth methods (`ghp_` works via URL-embedded auth, `gho_` requires `GIT_ASKPASS`, `github_pat_` untested), adding confusion.

For new developers, operators provisioning cloud VMs, or anyone restoring to a fresh machine, this friction is the first thing they hit — and it's entirely avoidable with a standard OAuth device flow.

## Solution overview

Add a **GitHub Device Authorization Flow** (OAuth device flow) as a fallback authentication method. When `GITHUB_TOKEN` is not provided, the bootstrap script starts a device flow:

1. Prints `Visit https://github.com/login/device and enter code: ABCD-1234`
2. Polls GitHub's device flow API until the user authorises
3. Receives a short-lived token and proceeds with the restore

The device flow is designed for CLI tools on headless machines — the user authenticates from any device with a browser (phone, laptop, etc.). No client secret is needed because the flow is public by design.

**Priority**: `GITHUB_TOKEN` env var > device flow fallback. Existing PAT-based workflows continue unchanged.

## User stories

1. **Fresh machine restore (no token)**: A user runs `curl .../magic-setup.sh | bash` without setting `GITHUB_TOKEN`. The script detects no token, starts the device flow, prints the URL and code, polls until authorised, and completes the restore.

2. **Existing PAT workflow unchanged**: A user with a `GITHUB_TOKEN` env var runs the same command. The script uses the token directly, no device flow is triggered. Zero regression.

3. **Headless SSH target**: A user SSHes into a fresh cloud VM, runs the restore command, sees the device flow prompt on their terminal. They open the URL on their laptop, enter the code, and the restore completes without them ever leaving their terminal.

4. **Slow network restore**: The device flow times out while waiting for user authorisation (15-minute GitHub window). The script prints a clear error and allows re-running.

5. **Fork/user-owned OAuth App**: A user who forks the repo sets `GITHUB_OAUTH_CLIENT_ID=their_client_id` to use their own registered OAuth App instead of the default.

6. **Re-auth after session end**: A user needs to run `sync-repos.sh` or `restore-data.sh` in a new terminal. They're prompted to re-authenticate via the device flow (token not persisted). The re-auth is fast (~10 seconds).

## Implementation decisions

### Decision 1: GitHub Device Authorization Flow (OAuth device flow)

**Chosen**. Standard OAuth flow for CLI/headless environments. No client secret needed. Poll-based: the script polls `POST https://github.com/login/device/code` for the access token after the user authorises.

- **Rejected alternatives**: `gh auth login` (requires `gh` binary), SSH key (doesn't cover API), GitHub App (overkill), status quo (too much friction).

### Decision 2: `GITHUB_TOKEN` > device flow fallback

**Chosen**. If `GITHUB_TOKEN` is set, use it directly. If absent, start the device flow. This is a one-line conditional in `magic-setup.sh` and `bootstrap-orchestrator.sh`. Non-breaking.

### Decision 3: Scope — `repo` only

**Chosen**. Minimum required scope. `repo` covers cloning private repos and reading release assets. No `read:user`, no `write:repo`, no `workflow`.

### Decision 4: OAuth App under `ak47-arch` account, client_id overridable

**Chosen**. The device flow `client_id` is public by design, so it's safe to bake into the script. Overridable via `GITHUB_OAUTH_CLIENT_ID` env var for forks.

### Decision 5: Print URL + code, never auto-open

**Chosen**. Universal — works regardless of whether the target machine has a display, browser, or `xdg-open`.

### Decision 6: Token not persisted

**Chosen**. The token is used in-memory for the restore session, then discarded. Re-authentication is required for a new terminal session. This is acceptable for now; persistence can be added later if the UX becomes a pain point.

### Decision 7: Shell script + Python lib split

**Chosen**. `github-auth-device-flow.sh` is the interactive shell script (prints prompts, calls Python). `device_flow_auth()` in `portability_lib.py` holds the polling logic. This keeps the shell script clean and makes the Python function reusable.

### Decision 8: 5-minute polling timeout

**Chosen**. GitHub allows 15 minutes for device flow. The script polls for 5 minutes with a clear spinner, then advises the user to re-run if it expires. The user can always re-run instantly.

### Decision 9: `repo` scope requested

**Chosen**. Required for cloning private repos and reading release assets. The OAuth app's requested scopes are `repo`.

## Testing decisions

### Seam

The feature will be tested at the **Python function level** (`device_flow_auth()` in `portability_lib.py`) and at the **integration level** (end-to-end device flow with a real GitHub OAuth App).

### Test cases

1. **Unit — `device_flow_auth()` polling**: Mock the GitHub API responses. Verify correct polling loop, timeout handling, error handling for expired codes, incorrect codes, rate limits.

2. **Integration — manual device flow test**: Run `github-auth-device-flow.sh` on a real machine, verify the URL and code print correctly, authorise via browser, verify the token is received and usable for `git clone`.

3. **Regression — PAT still works**: Verify that `GITHUB_TOKEN=ghp_xxx bootstrap-orchestrator.sh --dest /tmp/test` works without triggering the device flow.

4. **Regression — restore-workspace.sh unchanged**: Verify that `restore-workspace.sh` still works with `--github-token` flag (no changes needed to that script, but confirm).

### Non-goals for testing

- No automated end-to-end test against the real GitHub API (requires a real OAuth App and user interaction).
- No CI/CD integration for the device flow test (it's interactive by nature).

## Out-of-scope items

- **Token persistence**: No `~/.workspace-portability/token` file or keyring integration. Addressed in the decision record — revisit if UX becomes a pain point.
- **rclone/Google Drive OAuth**: The research doc flagged that rclone config for Google Drive is also a fresh-machine blocker. This PRD covers only GitHub auth. Google Drive auth is a separate effort.
- **`cloud-full` and `llm-node` profiles**: These remain unimplemented per the existing PORTABILITY_PLAN.md. Unrelated to this change.
- **pi installation**: Deferred per existing PRD. No change.
- **Windows/macOS support**: Device flow is platform-agnostic by design, but the bootstrap scripts target Ubuntu/Debian. No platform changes in this PRD.

## Further notes

### Existing code affected

**Will change:**
- `magic-setup.sh` — add device flow call when `GITHUB_TOKEN` is absent
- `bootstrap-orchestrator.sh` — add device flow call when `GITHUB_TOKEN` is absent
- `portability_lib.py` — add `device_flow_auth()` function
- New file: `github-auth-device-flow.sh` — interactive shell wrapper

**Will NOT change:**
- `restore-workspace.sh` — already passes `GITHUB_TOKEN` through `GIT_ASKPASS`
- `restore_workspace.py` — already accepts `--github-token`
- `restore_data.py` — already accepts `--github-token`
- `sync_repos.py` — already uses `GIT_ASKPASS` if set
- `create_workspace_critical_snapshot.sh` — no auth changes needed
- `setup-guide.sh` — Phase 2, unaffected

### Device flow API details

```
Step 1: POST https://github.com/login/device/code
  → {"device_code": "...", "user_code": "ABCD-1234",
     "verification_uri": "https://github.com/login/device",
     "expires_in": 900, "interval": 5}

Step 2: Print "Visit https://github.com/login/device and enter code: ABCD-1234"

Step 3: POST https://github.com/login/oauth/access_token
        (polling every `interval` seconds, up to `expires_in`)
  → {"access_token": "gho_...", "token_type": "bearer", "scope": "repo"}
  → or {"error": "authorization_pending"} → keep polling
  → or {"error": "expired_token"} → restart flow
  → or {"error": "access_denied"} → user declined, abort
```

### Rate limits

GitHub allows 50 device flow requests per hour per `client_id`. For a restore flow that runs once per machine, this is irrelevant. If a user retries rapidly, they may hit the limit — the script should print a clear message and advise waiting.

### Session evidence

The restore drill on themistocles (2026-06-19/20, documented in `WORKSPACE_MAGIC_SETUP_PRD.md` Section 22) motivated this work. The drill showed that PAT-based auth on a fresh machine is fragile and confusing across token types, which is the exact problem the device flow solves.