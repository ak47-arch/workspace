# Workspace Backup and Recovery

Date: 2026-05-24
Workspace root: `/home/anupam/Desktop/workspace`
Skill location: `/home/anupam/Desktop/workspace/.pi/skills/workspace-backup-recovery`

This document describes the current backup and recovery setup for the workspace.

Canonical standalone scripts now live in `/home/anupam/Desktop/workspace/workspace-portability`.
The skill wrappers in `.pi/skills/workspace-backup-recovery/` delegate to that directory.

## What is backed up

The canonical portability bundle now uses three restore inputs:

1. source code recovered from git remotes
2. critical local-only data recovered from the critical snapshot
3. large runtime assets recovered from a separate large-assets snapshot

### Recovered from git remotes

These repositories are restored from git during recovery:

- workspace root repo
- `agent-browser`
- `backup-tool`
- `emotional_architecture`
- `feed_analyser`
- `hermes`
- `llm`
- `pi-mono`
- `skills`
- `survival-infrastructure`

### Recovered from the critical snapshot tar

These local-only paths are restored from the critical snapshot:

- `survival-infrastructure/data`
- `survival-infrastructure/data-prod`
- `survival-infrastructure/data_prod_copy`
- `survival-infrastructure/.runtime-data`
- `survival-infrastructure/.env`
- `feed_analyser/backend/data.db`
- `feed_analyser/backend/raw_data`
- `feed_analyser/backend/archive`
- `hermes/.hermes-data`

## Snapshot creation

Canonical critical snapshot creation script:

- `workspace-portability/create_workspace_critical_snapshot.sh`

Canonical critical snapshot wrapper:

- `workspace-portability/create-snapshot.sh`

Canonical large-assets snapshot wrapper:

- `workspace-portability/create-large-assets-snapshot.sh`

Canonical combined wrapper:

- `workspace-portability/create-all-snapshots.sh`

The skill wrappers forward to the critical snapshot scripts.

What it does:

1. stages the critical local-only data into a temporary snapshot directory
2. excludes obvious cache junk inside `hermes/.hermes-data`
3. creates a **single tar.gz** using `backup-tool/backup.sh`
4. keeps only the latest local snapshot (`--retention 1`)
5. uploads the tar and checksum to Google Drive via `rclone`

### Hermes exclusions

The snapshot intentionally excludes the following Hermes cache/runtime paths to keep the backup smaller:

- `.hermes-data/.cache`
- `.hermes-data/.npm`
- `.hermes-data/audio_cache`
- `.hermes-data/image_cache`
- `.hermes-data/logs`
- `.hermes-data/cache`
- `.hermes-data/ollama_cloud_models_cache.json`
- `.hermes-data/models_dev_cache.json`
- `.hermes-data/.update_check`

### Local snapshot location

- `/home/anupam/Desktop/backup_data/workspace-critical-snapshot/`

Current behavior:
- one local tar retained
- one matching `.sha256` retained

### Cloud upload locations

The critical snapshot currently uploads to:

- `workspace:workspace-critical-snapshot`

The large-assets snapshot currently uploads to:

- `workspace:workspace-large-assets`

These are the currently configured `rclone` Google Drive remote paths.

## Snapshot commands

Run from the canonical directory:

```bash
cd /home/anupam/Desktop/workspace/workspace-portability
./create-snapshot.sh
```

Or use the skill wrapper, which delegates to the same implementation.

Useful variants:

```bash
# Create local snapshot only, skip Drive upload
UPLOAD_TO_DRIVE=false ./create-snapshot.sh
```

```bash
# Use a different rclone remote/path
RCLONE_REMOTE='workspace:workspace-critical-snapshot' ./create-snapshot.sh
```

```bash
# Dry-run
UPLOAD_TO_DRIVE=false ./create-snapshot.sh --dry-run
```

## Recovery

Canonical repo + critical-state recovery script:

- `workspace-portability/restore_workspace.py`

Canonical wrapper:

- `workspace-portability/restore-workspace.sh`

Additional canonical orchestration scripts:

- `workspace-portability/materialize-secrets.sh`
- `workspace-portability/hydrate-large-assets.sh`
- `workspace-portability/setup-workspace.sh`
- `workspace-portability/start-services.sh`
- `workspace-portability/full-restore.sh`
- `workspace-portability/test-restore.sh`

Restore manifest:

- `workspace-portability/workspace_restore_manifest.json`

What recovery does:

1. finds the latest snapshot tar on Drive
2. downloads the tar and checksum
3. verifies the checksum
4. extracts the snapshot
5. clones/fetches all repos into the right workspace layout
6. checks out the configured branch for each repo
7. restores the local-only data back into the correct paths

### Restore command

```bash
cd /home/anupam/Desktop/workspace/workspace-portability
./restore-workspace.sh /path/to/restored-workspace
```

### Full portable restore

```bash
cd /home/anupam/Desktop/workspace/workspace-portability
./full-restore.sh /path/to/restored-workspace --start
```

### Restore a specific snapshot

```bash
./restore-workspace.sh \
  /path/to/restored-workspace \
  --artifact workspace_critical_snapshot_20260524_213956.tar.gz
```

### Restore from an already downloaded local tar

```bash
./restore-workspace.sh \
  /path/to/restored-workspace \
  --skip-download \
  --local-artifact /home/anupam/Desktop/backup_data/workspace-critical-snapshot/workspace_critical_snapshot_20260524_213956.tar.gz
```

### Run the Python restore script directly

```bash
python3 ./restore_workspace.py /path/to/restored-workspace
```

## Recovery assumptions

The restore flow depends on these remaining valid:

- the repo URLs in `workspace_restore_manifest.json`
- the configured default branches in `workspace_restore_manifest.json`
- the snapshot existing in Google Drive
- `git`, `python3`, `tar`, and `rclone` being installed on the recovery machine

If a repo remote or branch changes later, update the manifest.

## Important operational notes

- The restore script is designed for **disaster recovery / workspace replication**.
- It is intentionally convergent and may overwrite existing restored data paths.
- It hard-resets repositories to the configured remote branch.
- It does **not** restore:
  - `.venv`
  - `node_modules`
  - caches
  - GGUF model files

Those are expected to be recreated or restored separately if needed.

## Current known limitation

The current cloud remote is plain Google Drive remote `workspace:`.
That means Drive-side storage is not additionally encrypted by `rclone crypt`.
The canonical snapshot scripts now support optional `age` encryption for uploaded artifacts, but the remote itself is still not an encrypted `crypt` backend.

## Bundled files in this skill

- `SKILL.md`
- `WORKSPACE_BACKUP_AUDIT.md`
- `WORKSPACE_BACKUP_RECOVERY.md`
- `create-snapshot.sh`
- `restore-workspace.sh`
- `create_workspace_critical_snapshot.sh`
- `restore_workspace.py`
- `workspace_restore_manifest.json`

## Recommended recurring workflow

1. run the snapshot script after meaningful local-data changes
2. confirm the tar and `.sha256` exist locally
3. confirm the files appear in Drive via `rclone ls workspace:workspace-critical-snapshot`
4. periodically test restore into a scratch directory
