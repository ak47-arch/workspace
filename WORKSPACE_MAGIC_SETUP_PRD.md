# PRD: One-Command Workspace Magic Setup

Date: 2026-05-30
Last updated: 2026-06-06
Status: In Progress — Milestones 1 & 2 complete, M3 in design
Owner: Workspace portability initiative

## 1. Summary

We want a single command that can take a brand new laptop or cloud machine and turn it into a fully working workspace environment.

The end-user experience should feel like:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/ak47-arch/workspace-portability/main/magic-setup.sh \
  | bash -s -- --profile laptop
```

Then the user should be able to sit back and watch the machine:

1. install host dependencies
2. install pi
3. clone and restore the workspace
4. restore critical local-only data (non-sensitive runtime state)
5. fetch required large assets
6. generate secret templates and guide user through providing API keys
7. rebuild environments
8. start services
9. verify health
10. report success

This PRD defines the product requirements and implementation direction to get there.

---

## 2. Problem

Today, the project has a strong script-first portability foundation in `workspace-portability/`, but setup is not yet truly one-command or magical.

Current gaps:

- ~~the canonical scripts live inside the workspace, so the workspace must exist before the scripts can run~~ **[RESOLVED — magic-setup.sh + bootstrap-orchestrator.sh built 2026-06-06]**
- secrets are not yet separated into auto-restored data vs. user-provided credentials — the snapshot currently contains real API keys, which is a security risk
- large assets are not yet automatically fetched in a profile-driven way
- pi installation is not yet part of the canonical end-to-end setup flow
- ~~cloud and laptop targets are not yet modeled as first-class profiles~~ **[RESOLVED — laptop/minimal/cloud-app profiles built 2026-06-06]**
- local runtime assumptions like `LLAMA_CPP_DIR` are still host-specific and not normalized
- the snapshot `.env` contains real OpenRouter API keys — these should not be shipped to new machines

As a result, the system is strong for disaster recovery and deterministic restores, but not yet at the desired level of one-command setup for new laptops or cloud hosts.

---

## 3. Vision

Given a blank supported machine plus credentials, a single command should fully prepare the machine for a requested profile and verify that it is usable.

The system should support both:

- new developer laptops
- cloud runtime nodes

and should work with minimal or no manual intervention beyond required authentication.

**Security principle:** Secrets that are spendable, personal, or machine-specific (API keys, llama.cpp paths) must NOT be auto-shipped. The system auto-restores only non-sensitive runtime data (event logs, databases of ingested content). For everything else, it generates templates and guides the user through providing their own values.

---

## 4. Goals

### Primary goals

1. Support one-command setup for new laptops.
2. Support one-command setup for cloud machines.
3. Make setup profile-driven rather than ad hoc.
4. Keep the canonical implementation script-first and automatable.
5. Ensure required large assets can be downloaded automatically.
6. Ensure pi can be installed automatically where needed.
7. End every setup with machine-verifiable checks.
8. **Separate auto-restored data from user-provided secrets** — runtime data is automatic; API keys and host-specific paths are guided with clear instructions.

### Secondary goals

1. Keep the restore/bootstrap process idempotent.
2. Preserve disaster recovery workflows already built in `workspace-portability/`.
3. Support gradual rollout from local-only secrets/assets toward more cloud-native providers.
4. Make the system testable via repeatable restore drills.
5. New developers can onboard without receiving pre-existing credentials.

---

## 5. Non-goals

For the first version, this PRD does not require:

- Windows support
- offline installation
- support for every Linux distro
- support for every optional repo feature or subproject
- full removal of all host-specific assumptions in one step

Initial target environment:

- Ubuntu/Debian laptops
- Ubuntu/Debian cloud VMs
- current workspace structure and repos

---

## 6. Users

### Developer with a new laptop
Needs a single command to recreate the full working workspace, including pi and required local tools. Must be guided through providing their own API keys and paths rather than inheriting someone else's credentials.

### Operator recovering to a cloud VM
Needs a single command to recreate a working runtime host with minimal manual intervention.

### Operator provisioning a dedicated LLM node
Needs a single command to provision the local inference runtime and required model assets.

### New developer joining the project
Needs clear documentation on what credentials to obtain (OpenRouter key, GitHub PAT) and where to place them — without receiving copies of existing keys.

---

## 7. Profiles

The system supports four first-class profiles.

### 7.1 `laptop`
Target: full developer machine

Expected behavior:

- install host dependencies (git, python, node, docker, rclone, uv, pnpm, age)
- install pi
- clone/restore all workspace repos
- restore critical local-only runtime data
- download required large assets (model GGUF files)
- generate .env template with placeholders — guide user to fill in OpenRouter key, llama.cpp path
- rebuild environments (python venvs, npm/pnpm installs)
- optionally start canonical local services
- verify success (warn if secrets are still placeholders)

### 7.2 `minimal`
Target: secondary/constrained machines (e.g., ingestion nodes, low-RAM laptops)

Expected behavior:

- install host dependencies (git, python, rclone, curl — NO docker, NO node, NO large assets)
- clone/restore core workspace repos
- restore critical local-only runtime data
- skip large assets and local LLM entirely
- generate .env template — guide user to point LLM_BASE_URL at a remote inference server
- rebuild Python environments only
- do NOT start services
- verify success

### 7.3 `cloud-app`
Target: cloud application/runtime host

Expected behavior:

- install host dependencies (git, python, docker, rclone)
- clone/restore required repos
- restore critical local-only runtime data
- do not require local GGUFs
- use a remote LLM endpoint (user configures during setup)
- start app services
- verify success

### 7.4 `llm-node`
Target: dedicated inference host

Expected behavior:

- install host dependencies
- restore/setup only what is needed for LLM runtime
- fetch required model assets
- provision llama.cpp/runtime
- expose healthy inference endpoints
- verify success

---

## 8. Product requirements

### 8.1 One-command bootstrap
The system must provide a single command entrypoint that works before the workspace exists on disk.

Examples:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/ak47-arch/workspace-portability/main/magic-setup.sh \
  | bash -s -- --profile laptop
```

### 8.2 Script-first canonical implementation
The core setup logic must remain deterministic, script-first, and non-interactive where possible.

The pi skill layer may wrap the system, but must not be required for recovery or bootstrap.

### 8.3 Workspace acquisition
The system must automatically clone the workspace root repo and then use the canonical restore manifest to restore all required repos on the correct branches.

### 8.4 Critical data restore
The system must restore critical local-only workspace data from the critical snapshot. This is limited to non-sensitive runtime state: event logs (JSONL), SQLite databases, hermes session state, and similar. It does NOT include API keys or credentials (see 8.6).

### 8.5 Large asset restore/hydration
The system must automatically download or hydrate large assets required by the selected profile.

Examples include:

- `llm/gemma`
- `survival-infrastructure/llm/gemma`

### 8.6 Secrets materialization (REFINED — 2026-06-06)
The system must distinguish between two classes of configuration:

**Class A — Auto-restored runtime data** (from critical snapshot):
- Event logs, SQLite databases, hermes session state
- Non-sensitive, non-spendable, machine-portable
- Restored automatically with no user intervention

**Class B — User-provided secrets** (NOT in snapshot):
- OpenRouter API key (spendable — each developer brings their own)
- LLAMA_CPP_DIR path (machine-specific)
- Remote LLM endpoint URLs (environment-specific)
- GitHub PAT (provided at invocation time, not stored)

For Class B, the system must:
1. Generate template `.env` files with documented placeholders
2. Print clear instructions to the user: what keys are needed, where to obtain them, where to place them
3. Validate that required secrets are present (not still placeholders) before declaring success
4. NEVER ship real API keys in the snapshot to a new machine

### 8.7 Environment rebuild
The system must run deterministic setup steps for required repos, including Python and Node environments.

### 8.8 pi installation
For profiles that require it, the system must install pi automatically and verify it is usable.

### 8.9 Startup orchestration
The system must start the correct services for the selected profile.

### 8.10 Verification
The system must end with machine-verifiable checks, including:

- repo presence and correct branches
- restored critical paths
- restored or downloaded large assets
- secret presence (warn if placeholders found)
- service health checks where applicable

---

## 9. Architecture

The target architecture has three layers.

### 9.1 Layer 0: bootstrap layer (`magic-setup.sh`)
A minimal setup artifact that works before the workspace exists.

Responsibilities:

- detect OS
- install minimal prerequisites (git, curl)
- clone `workspace-portability` to a temp directory
- hand off into the profile-driven orchestrator (`bootstrap-orchestrator.sh`)

### 9.2 Layer 1: canonical workspace portability bundle (`workspace-portability/`)
The existing `workspace-portability/` directory remains the source of truth for:

- restore
- critical snapshots
- large asset hydration
- secret materialization
- environment setup
- startup
- verification

### 9.3 Layer 2: profile-driven orchestration (`bootstrap-orchestrator.sh` + `profiles/`)
A higher-level orchestration layer selects behavior based on the requested profile.

Reads profile configs from `profiles/<name>.conf` and calls the Layer 1 scripts with appropriate flags.

---

## 10. Packaging strategy (UPDATED — 2026-06-06)

**Decision:** Extend the existing `workspace-portability` repo rather than creating a separate `workspace-bootstrap` repo.

### 10.1 Keep `workspace-portability/` as canonical core
This remains the source of truth for the actual restore/setup/start/verify logic.

### 10.2 `magic-setup.sh` lives at the root of `workspace-portability/`
The curl-able entrypoint is a self-contained script at the repository root. When executed, it clones `workspace-portability` to `/tmp`, then hands off to `bootstrap-orchestrator.sh`.

### 10.3 Profile configs live in `profiles/`
Each profile is a simple shell-sourced `.conf` file with boolean and string flags. The orchestrator reads the profile and maps it to existing script invocations.

### Rationale for single-repo approach
- Shared manifest (`workspace_restore_manifest.json`) co-evolves with the scripts that read it
- `portability_lib.py` is reused rather than duplicated
- No repo proliferation — one repo for all workspace operations
- `magic-setup.sh` is versioned alongside the scripts it calls
- GitHub private repo ACL provides built-in access control for onboarding

---

## 11. Manifest evolution

The current `workspace-portability/workspace_restore_manifest.json` should evolve into a profile-aware manifest.

It should eventually define:

- supported profiles
- host dependency profiles
- repo restore topology
- critical restore paths (non-sensitive runtime data only)
- large assets by profile
- secrets expectations by profile (templates, not values)
- setup steps by profile
- startup targets by profile
- verification checks by profile

### Example future shape

```json
{
  "profiles": {
    "laptop": { ... },
    "cloud-app": { ... },
    "cloud-full": { ... },
    "llm-node": { ... }
  }
}
```

---

## 12. Secrets strategy (REFINED — 2026-06-06)

### Core principle: Guide, don't copy

The critical snapshot must NOT contain real API keys or spendable credentials. It contains only non-sensitive runtime data. Secrets are the user's responsibility — the system guides them through providing them.

### Two data classes

| Class | Contents | Restore method | Examples |
|---|---|---|---|
| **Runtime data** | Non-sensitive, non-spendable | Auto-restored from critical snapshot | Event logs (JSONL), SQLite DBs, hermes session state |
| **User secrets** | Spendable, personal, machine-specific | Template generation + guided setup | OpenRouter API key, LLAMA_CPP_DIR, GitHub PAT |

### Snapshot cleanup required

The critical snapshot script (`create_workspace_critical_snapshot.sh`) must be updated to either:
- Exclude `.env` files entirely (they'll be generated from templates)
- Or redact sensitive values from `.env` before snapshotting, leaving `OPENROUTER_API_KEY=YOUR_KEY_HERE`

### Template generation

For each profile, the system generates `.env` templates with placeholders:

```bash
# survival-infrastructure/.env (generated template)
# ── REQUIRED: OpenRouter API key ─────────────────────────────────
# Get your key at: https://openrouter.ai/keys
OPENROUTER_API_KEY=YOUR_OPENROUTER_API_KEY_HERE

# ── REQUIRED: llama.cpp binary location ──────────────────────────
# Clone from https://github.com/ggerganov/llama.cpp and build, or install via package manager.
# Point this at the directory containing llama-server.
SURVIVAL_LLAMA_CPP_DIR=/opt/llama-cpp

# ── LLM routing ──────────────────────────────────────────────────
SURVIVAL_LLM_BASE_URL=http://127.0.0.1:8012
```

### Planned provider abstraction (future)

For zero-touch secrets in cloud environments, the system may eventually support:

- `local-dir` — fallback
- `template` — generate placeholders with docs (current approach)
- `1password` / `bitwarden` — laptop
- `aws-secrets-manager` / `gcp-secret-manager` — cloud

### Provider contract

A secrets provider must be able to:

1. identify which secrets are needed for the profile
2. write template files with placeholders
3. print human-readable instructions for obtaining each secret
4. validate that real values (not placeholders) are present before declaring success

---

## 13. Large asset strategy

Required large assets must be automatically downloadable for the selected profile.

### Requirements

The asset system must support a provider abstraction.

Planned providers:

- `local`
- `gdrive` (current — rclone)
- `s3`
- `gcs`
- `r2`

### Recommended direction

Use object storage as the long-term canonical asset source.
Google Drive via rclone is the current backend and works for snapshot artifacts.

### Asset metadata requirements

Each large asset should eventually define:

- logical name
- destination path
- provider/backend
- object key or artifact name
- checksum
- compression format
- required profiles

---

## 14. pi installation strategy

pi must become a deterministic part of the setup flow for profiles that require it.

### Requirement

For `laptop`, pi must be installed and verified automatically.

### Recommended direction

Use a manifest-driven install step tied to the existing `pi-mono` repo, with a deterministic build/install path and a final validation such as:

```bash
pi --help
```

---

## 15. Host normalization

The system must reduce host-specific assumptions.

### Current issue

Variables like these are still too host-dependent:

- `LLAMA_CPP_DIR`
- `SURVIVAL_LLAMA_CPP_DIR`

### Requirement

The system should move toward deterministic install locations or standardized runtime conventions for local LLM hosting.

### Recommended direction

Normalize local LLM runtime installation to a known path such as:

- `/opt/llama-cpp`
- or a workspace-managed deterministic location

The `.env` template should document this convention and let the user override if their setup differs.

---

## 16. Cloud requirements

### 16.1 Cloud app hosts
`cloud-app` must not require local model assets.
It should use a remote LLM endpoint.

### 16.2 Cloud full hosts
`cloud-full` must be able to restore and start a fully self-hosted runtime, including local models and LLM runtime.

### 16.3 Dedicated LLM hosts
`llm-node` must be able to provision and verify a dedicated inference service independently.

---

## 17. User flows

### 17.1 New laptop flow
User runs:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
curl -fsSL .../magic-setup.sh | bash -s -- --profile laptop
```

System behavior:

1. bootstrap host (install git, python, docker, node, rclone, uv, pnpm)
2. clone workspace and all sub-repos from GitHub
3. restore critical runtime data from snapshot (event logs, DBs, session state)
4. fetch large assets (model GGUF files) as needed
5. generate .env templates with placeholders
6. print guidance: "Obtain an OpenRouter key at https://openrouter.ai/keys and add it to survival-infrastructure/.env"
7. rebuild environments (python venvs, npm/pnpm installs)
8. optionally start services
9. verify — warn if .env still contains placeholders
10. report success (or list remaining manual steps)

### 17.2 New developer onboarding flow
Developer receives the onboarding doc which tells them:

1. Create a GitHub fine-grained PAT with read access to `workspace-portability`
2. Run the curl command above
3. Get an OpenRouter API key at https://openrouter.ai/keys
4. Edit `survival-infrastructure/.env` and paste the key
5. Install llama.cpp at `/opt/llama-cpp` (or set LLAMA_CPP_DIR)
6. Run `./start_stack.sh` when ready

The developer never receives a copy of anyone else's API keys.

### 17.3 Cloud app host flow
User runs:

```bash
export GITHUB_TOKEN=ghp_...
curl .../magic-setup.sh | bash -s -- --profile cloud-app
```

System behavior:

1. bootstrap host
2. clone workspace
3. restore repos and critical data
4. skip local model assets
5. generate templates, guide through secrets
6. rebuild envs
7. configure remote LLM endpoint
8. start app services
9. verify success

### 17.4 Full cloud host flow
User runs:

```bash
export GITHUB_TOKEN=ghp_...
curl .../magic-setup.sh | bash -s -- --profile cloud-full
```

System behavior:

1. bootstrap host
2. clone workspace
3. restore repos and critical data
4. fetch model assets
5. provision local LLM runtime
6. rebuild envs
7. start app + llm services
8. verify success

---

## 18. Acceptance criteria

### Global acceptance criteria

A supported machine can be prepared from a single command. Non-sensitive runtime data is auto-restored. Secrets are guided with clear instructions. No real API keys are shipped in the snapshot.

### `laptop`
After completion:

- workspace exists and verifies successfully
- critical runtime data exists
- required large assets exist
- pi is installed and usable
- .env template exists with clear placeholder instructions
- user can fill in their own keys and start services
- verification passes (warns on unresolved placeholders)

### `minimal`
After completion:

- workspace exists and verifies successfully
- critical runtime data exists (event logs, SQLite DBs)
- no Docker, no Node.js, no large assets installed
- .env template exists with remote LLM routing instructions
- user can configure LLM endpoint and start consuming
- verification passes

### `cloud-app`
After completion:

- workspace exists and verifies successfully
- critical runtime data exists
- no local GGUF requirement exists
- .env configured for remote LLM endpoint
- app services start successfully against remote LLM
- verification passes

### `cloud-full`
After completion:

- workspace exists and verifies successfully
- critical runtime data exists
- large assets exist
- local LLM runtime is healthy
- app services are healthy
- verification passes

### `llm-node`
After completion:

- required repos exist
- model assets exist
- local LLM runtime is healthy
- verification passes

---

## 19. Risks

### 19.1 Secret auth friction
A secrets provider may still require human authentication.

Mitigation:
- template approach with clear instructions is the default
- value presence is validated before declaring success
- cloud-native providers can be added later for zero-touch

### 19.2 Large asset download time
Model and asset downloads may be slow.

Mitigation:
- resumable downloads (rclone handles this)
- checksums
- caching
- profile-driven selective download (minimal skips assets entirely)

### 19.3 Host package variance
Different machines may have different package availability.

Mitigation:
- officially support Ubuntu/Debian first

### 19.4 Runtime drift
Repo setup requirements may change over time.

Mitigation:
- manifest-driven setup
- automated restore drills

### 19.5 Accidental secret leakage via snapshot (NEW)
If `.env` files with real keys remain in the critical snapshot paths, any machine that restores that snapshot gets copies of spendable credentials.

Mitigation:
- exclude `.env` from snapshot, or redact values to placeholders
- `materialize-secrets.sh` validates that values are not placeholders
- profile-scoped secret requirements limit exposure

---

## 20. Milestones

### Milestone 1: Pre-workspace bootstrap ✅ COMPLETE (2026-06-06)
Delivered:

- `magic-setup.sh` — curl-able entrypoint at root of `workspace-portability/`
- `bootstrap-orchestrator.sh` — profile-driven orchestrator
- Minimal host bootstrap (installs git + curl) and workspace-portability clone handoff

Deferred from original plan:
- Chose to extend `workspace-portability` repo rather than create separate `workspace-bootstrap` repo (see Section 10)

### Milestone 2: Profile support ✅ COMPLETE (2026-06-06)
Delivered:

- `profiles/laptop.conf` — full developer machine
- `profiles/minimal.conf` — constrained/secondary machines (no Docker, no models)
- `profiles/cloud-app.conf` — cloud app host (Docker, remote LLM, no models)
- Orchestrator maps profile flags to existing script invocations

Not yet delivered:
- Profile-aware manifest (profiles still live as separate .conf files, not in manifest JSON)
- `cloud-full` and `llm-node` profiles

### Milestone 3: Secret materialization with template model 🔄 IN DESIGN
Deliver:

- Separate snapshot contents: runtime data (auto-restored) vs. secrets (template-generated)
- Update `create_workspace_critical_snapshot.sh` to exclude `.env` or redact sensitive values
- Update `materialize-secrets.sh` to generate `.env` templates with placeholders and instructions
- Add `--check-secrets` flag to verify that real values have replaced placeholders
- Document the onboarding flow: what keys to obtain, where to place them

### Milestone 4: Asset provider integration
Deliver:

- provider abstraction in asset hydration
- at least one canonical large-asset provider implemented
- rclone Google Drive is current backend; needs config materialization

### Milestone 5: pi installation
Deliver:

- deterministic pi installation for `laptop`
- pi verification step

### Milestone 6: Host normalization
Deliver:

- normalized LLM runtime path/install conventions (e.g., `/opt/llama-cpp`)
- reduced host-specific manual config
- `.env` template documents the convention, user can override

### Milestone 7: End-to-end magic flows
Deliver:

- one-command `laptop` — tested on a fresh machine
- one-command `minimal` — tested on themistocles or similar
- one-command `cloud-app`
- one-command `cloud-full`
- one-command `llm-node`

### Milestone 8: Automated drills
Deliver:

- repeatable laptop/cloud test runs
- restore/setup/start verification in fresh environments

---

## 21. Open decisions

### Resolved (2026-06-06)

1. **Canonical bootstrap artifact?**
   → Extend `workspace-portability` repo. `magic-setup.sh` lives at repo root. No separate `workspace-bootstrap` repo.

2. **Secrets model?**
   → Template + guided setup. No real API keys in snapshots. Runtime data auto-restored; credentials are user-provided.

### Still open

1. What is the primary laptop secrets provider for future zero-touch? (1Password? Bitwarden?)
2. What is the primary cloud secrets provider? (AWS? GCP?)
3. What is the canonical large asset storage backend beyond Google Drive? (S3? R2?)
4. What is the deterministic pi install path?
5. Should `cloud-app` always require remote LLM rather than local models? → Tentative: yes
6. Should rclone config for Google Drive snapshot access be auto-provisioned or user-configured?
7. Should templates be in-repo (committed to git) or generated dynamically by `materialize-secrets.sh`?
8. What is the canonical `LLAMA_CPP_DIR` path? `/opt/llama-cpp`? Workspace-relative?

---

## 22. Current status and next steps

### Completed (2026-06-06)

| Component | Status |
|---|---|
| `magic-setup.sh` (Layer 0) | ✅ Built, syntax-verified |
| `bootstrap-orchestrator.sh` (Layer 1) | ✅ Built, syntax-verified, dry-run tested |
| `profiles/laptop.conf` | ✅ Built |
| `profiles/minimal.conf` | ✅ Built |
| `profiles/cloud-app.conf` | ✅ Built |
| Existing `workspace-portability/` scripts | ✅ Unchanged, fully integrated |

### Immediate next step (Milestone 3, first half)

**Secure the critical snapshot — remove real secrets.**

1. Update `create_workspace_critical_snapshot.sh` to exclude `survival-infrastructure/.env` from the snapshot (or redact `OPENROUTER_API_KEY` to a placeholder)
2. Create a `.env.template` file in `survival-infrastructure/` that is committed to git (contains placeholders and instructions)
3. Update `materialize-secrets.sh` to copy `.env.template` → `.env` if `.env` doesn't exist, and validate that real values (not placeholders) are present
4. Create new critical snapshots with the updated exclude list
5. Test the full flow on themistocles with `--profile minimal`

### Next after that

- Add rclone config materialization so snapshots can be pulled from Google Drive on any machine (not just LAN)
- Build `cloud-full` and `llm-node` profiles
- Test `--profile laptop` on a fresh VM to validate the end-to-end flow
