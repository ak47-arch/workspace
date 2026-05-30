# PRD: One-Command Workspace Magic Setup

Date: 2026-05-30
Status: Draft
Owner: Workspace portability initiative

## 1. Summary

We want a single command that can take a brand new laptop or cloud machine and turn it into a fully working workspace environment.

The end-user experience should feel like:

```bash
curl -fsSL https://bootstrap.example.com/magic-setup.sh | bash -s -- --profile laptop
```

or:

```bash
magic-setup --profile cloud-app
```

Then the user should be able to sit back and watch the machine:

1. install host dependencies
2. install pi
3. clone and restore the workspace
4. restore critical local-only data
5. fetch required large assets
6. materialize secrets
7. rebuild environments
8. start services
9. verify health
10. report success

This PRD defines the product requirements and implementation direction to get there.

---

## 2. Problem

Today, the project has a strong script-first portability foundation in `workspace-portability/`, but setup is not yet truly one-command or magical.

Current gaps:

- the canonical scripts live inside the workspace, so the workspace must exist before the scripts can run
- secrets are not yet fully integrated with a real provider model for zero-touch setup
- large assets are not yet automatically fetched in a profile-driven way
- pi installation is not yet part of the canonical end-to-end setup flow
- cloud and laptop targets are not yet modeled as first-class profiles
- local runtime assumptions like `LLAMA_CPP_DIR` are still host-specific and not normalized

As a result, the system is strong for disaster recovery and deterministic restores, but not yet at the desired level of one-command setup for new laptops or cloud hosts.

---

## 3. Vision

Given a blank supported machine plus credentials, a single command should fully prepare the machine for a requested profile and verify that it is usable.

The system should support both:

- new developer laptops
- cloud runtime nodes

and should work with minimal or no manual intervention beyond required authentication.

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

### Secondary goals

1. Keep the restore/bootstrap process idempotent.
2. Preserve disaster recovery workflows already built in `workspace-portability/`.
3. Support gradual rollout from local-only secrets/assets toward more cloud-native providers.
4. Make the system testable via repeatable restore drills.

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
Needs a single command to recreate the full working workspace, including pi and required local tools.

### Operator recovering to a cloud VM
Needs a single command to recreate a working runtime host with minimal manual intervention.

### Operator provisioning a dedicated LLM node
Needs a single command to provision the local inference runtime and required model assets.

---

## 7. Profiles

The system should support four first-class profiles.

### 7.1 `laptop`
Target: full developer machine

Expected behavior:

- install host dependencies
- install pi
- clone/restore all workspace repos
- restore critical local-only state
- download required large assets
- rebuild environments
- optionally start canonical local services
- verify success

### 7.2 `cloud-app`
Target: cloud application/runtime host

Expected behavior:

- install host dependencies
- clone/restore required repos
- restore critical local-only state
- fetch secrets from cloud-capable secret source
- do not require local GGUFs
- use a remote LLM endpoint
- start app services
- verify success

### 7.3 `cloud-full`
Target: full self-hosted cloud environment

Expected behavior:

- do everything `cloud-app` does
- also fetch large model assets
- provision local LLM runtime
- start app services and local LLM
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
curl -fsSL https://bootstrap.example.com/magic-setup.sh | bash -s -- --profile laptop
```

or:

```bash
magic-setup --profile laptop
```

### 8.2 Script-first canonical implementation
The core setup logic must remain deterministic, script-first, and non-interactive where possible.

The pi skill layer may wrap the system, but must not be required for recovery or bootstrap.

### 8.3 Workspace acquisition
The system must automatically clone the workspace root repo and then use the canonical restore manifest to restore all required repos on the correct branches.

### 8.4 Critical data restore
The system must restore critical local-only workspace data from the critical snapshot.

### 8.5 Large asset restore/hydration
The system must automatically download or hydrate large assets required by the selected profile.

Examples include:

- `llm/gemma`
- `survival-infrastructure/llm/gemma`

### 8.6 Secrets materialization
The system must automatically retrieve and materialize required secrets and `.env` files for the selected profile.

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
- secret presence
- service health checks where applicable

---

## 9. Architecture

The target architecture has three layers.

### 9.1 Layer 0: bootstrap layer
A minimal setup artifact that works before the workspace exists.

Responsibilities:

- detect OS
- install minimal prerequisites
- fetch the bootstrap orchestrator
- clone the workspace
- hand off into the canonical workspace portability flow

### 9.2 Layer 1: canonical workspace portability bundle
The existing `workspace-portability/` directory remains the source of truth for:

- restore
- critical snapshots
- large asset hydration
- secret materialization
- environment setup
- startup
- verification

### 9.3 Layer 2: profile-driven orchestration
A higher-level orchestration layer selects behavior based on the requested profile.

---

## 10. Packaging strategy

### 10.1 Keep `workspace-portability/` as canonical core
This remains the source of truth for the actual restore/setup/start/verify logic.

### 10.2 Introduce a new bootstrap repo
Create a minimal repo, tentatively named:

- `workspace-bootstrap`

Responsibilities:

- pre-workspace bootstrap
- host preparation
- profile selection
- handoff into `workspace-portability/`

### 10.3 Optional hosted bootstrap script
Publish a hosted raw script or equivalent entrypoint that clones or fetches `workspace-bootstrap` and executes it.

---

## 11. Manifest evolution

The current `workspace-portability/workspace_restore_manifest.json` should evolve into a profile-aware manifest.

It should eventually define:

- supported profiles
- host dependency profiles
- repo restore topology
- critical restore paths
- large assets by profile
- secrets expectations by profile
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

## 12. Secrets strategy

A true one-command flow requires a real secrets model.

### Requirements

The system must support a provider abstraction for secrets.

Planned providers:

- `local-dir`
- `snapshot`
- `1password`
- `bitwarden`
- `aws-secrets-manager`
- `gcp-secret-manager`

### Recommended initial direction

- `laptop`: 1Password or Bitwarden
- `cloud-*`: AWS or GCP native secret manager
- `local-dir` remains a fallback

### Provider contract

A secrets provider must be able to:

1. fetch named secret material
2. write required secret files
3. render `.env` files or env values
4. validate required values exist

---

## 13. Large asset strategy

Required large assets must be automatically downloadable for the selected profile.

### Requirements

The asset system must support a provider abstraction.

Planned providers:

- `local`
- `gdrive`
- `s3`
- `gcs`
- `r2`

### Recommended direction

Use object storage as the long-term canonical asset source.
Google Drive can remain a temporary backend.

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
magic-setup --profile laptop
```

System behavior:

1. bootstrap host
2. clone workspace
3. restore repos and critical data
4. fetch secrets
5. fetch required large assets
6. rebuild envs
7. install pi
8. optionally start services
9. verify success

### 17.2 Cloud app host flow
User runs:

```bash
magic-setup --profile cloud-app
```

System behavior:

1. bootstrap host
2. clone workspace
3. restore repos and critical data
4. fetch secrets
5. skip local model assets
6. rebuild envs
7. configure remote LLM endpoint
8. start app services
9. verify success

### 17.3 Full cloud host flow
User runs:

```bash
magic-setup --profile cloud-full
```

System behavior:

1. bootstrap host
2. clone workspace
3. restore repos and critical data
4. fetch secrets
5. fetch model assets
6. provision local LLM runtime
7. rebuild envs
8. start app + llm services
9. verify success

---

## 18. Acceptance criteria

### Global acceptance criteria

A supported machine can be prepared from a single command with no manual workspace-specific intervention.

### `laptop`
After completion:

- workspace exists and verifies successfully
- critical data exists
- required large assets exist
- pi is installed and usable
- required setup steps completed
- verification passes

### `cloud-app`
After completion:

- workspace exists and verifies successfully
- critical data exists
- secrets exist
- no local GGUF requirement exists
- app services start successfully against remote LLM
- verification passes

### `cloud-full`
After completion:

- workspace exists and verifies successfully
- critical data exists
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
- allow a one-time auth step
- continue setup automatically afterward

### 19.2 Large asset download time
Model and asset downloads may be slow.

Mitigation:
- resumable downloads
- checksums
- caching
- profile-driven selective download

### 19.3 Host package variance
Different machines may have different package availability.

Mitigation:
- officially support Ubuntu/Debian first

### 19.4 Runtime drift
Repo setup requirements may change over time.

Mitigation:
- manifest-driven setup
- automated restore drills

---

## 20. Milestones

### Milestone 1: Pre-workspace bootstrap
Deliver:

- `workspace-bootstrap` repo
- `magic-setup.sh`
- minimal host bootstrap and workspace clone handoff

### Milestone 2: Profile support
Deliver:

- profile-aware manifest
- `--profile` support across canonical scripts

### Milestone 3: Secret provider integration
Deliver:

- provider abstraction in secret materialization
- at least one real provider implemented

### Milestone 4: Asset provider integration
Deliver:

- provider abstraction in asset hydration
- at least one canonical large-asset provider implemented

### Milestone 5: pi installation
Deliver:

- deterministic pi installation for `laptop`
- pi verification step

### Milestone 6: Host normalization
Deliver:

- normalized LLM runtime path/install conventions
- reduced host-specific manual config

### Milestone 7: End-to-end magic flows
Deliver:

- one-command `laptop`
- one-command `cloud-app`
- one-command `cloud-full`
- one-command `llm-node`

### Milestone 8: Automated drills
Deliver:

- repeatable laptop/cloud test runs
- restore/setup/start verification in fresh environments

---

## 21. Open decisions

The following decisions must be made before implementation is complete:

1. What is the canonical bootstrap artifact?
   - Recommendation: create `workspace-bootstrap`
2. What is the primary laptop secrets provider?
3. What is the primary cloud secrets provider?
4. What is the canonical large asset storage backend?
5. What is the deterministic pi install path?
6. Should `cloud-app` always require remote LLM rather than local models?
   - Recommendation: yes

---

## 22. Recommended next step

The next implementation step should be:

**Build the pre-workspace bootstrap layer**

This is the missing prerequisite for true one-command magic setup.

Without it, the system remains strong for restore and portability, but not yet magical from a blank machine.
