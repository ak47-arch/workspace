# Workspace Portability

Canonical standalone backup, recovery, bootstrap, setup, startup, and verification bundle for this workspace.

## Goal

Recreate the workspace on a fresh machine with deterministic shell/Python entrypoints, without requiring pi or skill invocation.

## Canonical entrypoints

- `./bootstrap-host.sh` — install or verify host prerequisites
- `./create-snapshot.sh` — create the critical local-state snapshot and optionally upload it
- `./create-large-assets-snapshot.sh` — create the large-assets snapshot and optionally upload it
- `./create-all-snapshots.sh` — create both snapshots
- `./restore-workspace.sh /path/to/workspace` — restore repos from git and critical local-only state from the snapshot
- `./materialize-secrets.sh /path/to/workspace` — verify/materialize required secret files and startup env inputs
- `./hydrate-large-assets.sh /path/to/workspace` — restore large assets such as model directories
- `./setup-workspace.sh /path/to/workspace` — install repo dependencies deterministically
- `./start-services.sh /path/to/workspace` — start the canonical runtime targets
- `./verify-workspace.sh /path/to/workspace` — verify repos, restore paths, large assets, secrets, and optionally services
- `./full-restore.sh /path/to/workspace` — orchestrate restore + secrets + assets + setup + optional startup
- `./test-restore.sh` — run a restore drill using the latest local artifacts

## Snapshot split

The portability bundle uses two snapshot classes:

### 1. Critical snapshot
Small, high-priority local-only state:

- `survival-infrastructure/data`
- `survival-infrastructure/data-prod`
- `survival-infrastructure/data_prod_copy`
- `survival-infrastructure/.runtime-data`
- `survival-infrastructure/.env`
- `feed_analyser/backend/data.db`
- `feed_analyser/backend/raw_data`
- `feed_analyser/backend/archive`
- `hermes/.hermes-data`

### 2. Large-assets snapshot
Expensive runtime payloads:

- `llm/gemma`
- `survival-infrastructure/llm/gemma`

## Security / encryption

Offsite snapshot uploads can now be encrypted with `age`.

Set one of:

```bash
export SNAPSHOT_ENCRYPTION=age
export AGE_RECIPIENT='age1...'
```

or:

```bash
export SNAPSHOT_ENCRYPTION=age
export AGE_RECIPIENTS_FILE=/path/to/age-recipients.txt
```

Restore encrypted artifacts with:

```bash
export AGE_IDENTITY_FILE=/path/to/private-key.txt
./restore-workspace.sh /opt/workspace --age-identity-file "$AGE_IDENTITY_FILE"
./hydrate-large-assets.sh /opt/workspace --age-identity-file "$AGE_IDENTITY_FILE"
```

If `SNAPSHOT_ENCRYPTION` is unset, uploads remain plain `.tar.gz` artifacts for backward compatibility.

## Fresh-machine flow

### 1. Prepare the host

```bash
cd workspace-portability
./bootstrap-host.sh
```

Minimal restore-only check:

```bash
./bootstrap-host.sh --check --restore-only
```

### 2. Create both snapshots

```bash
./create-all-snapshots.sh
```

Local-only dry-run:

```bash
UPLOAD_TO_DRIVE=false ./create-all-snapshots.sh --dry-run
```

### 3. Full restore to a fresh location

```bash
./full-restore.sh /opt/workspace --start
```

With local artifacts instead of remote download:

```bash
./full-restore.sh \
  /opt/workspace \
  --local-critical-artifact /path/to/workspace_critical_snapshot_YYYYMMDD_HHMMSS.tar.gz \
  --local-large-assets-artifact /path/to/workspace_large_assets_YYYYMMDD_HHMMSS.tar.gz \
  --start
```

### 4. Verify manually

```bash
./verify-workspace.sh /opt/workspace
./verify-workspace.sh /opt/workspace --services
```

## Host expectations

### Restore-only profile

Requires:

- `git`
- `python3`
- `tar`
- `rclone`

### Full profile

Requires:

- restore-only tools
- `uv`
- `node`
- `npm`
- `pnpm`
- `docker`
- `docker-compose` (or `docker compose` with wrapper)
- `age`

`bootstrap-host.sh` installs or provisions these on supported Linux package managers.

## Manifest

`workspace_restore_manifest.json` is the single source of truth for:

- repos and branches
- critical restore paths
- large assets
- secrets expectations
- setup steps
- startup targets
- host dependency profiles

## Relationship to the pi skill

The skill at `.pi/skills/workspace-backup-recovery/` acts as a wrapper around this canonical bundle.

Recovery should always remain runnable directly from shell on a fresh machine.
